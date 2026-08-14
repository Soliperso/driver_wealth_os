import "@supabase/functions-js/edge-runtime.d.ts";

import { errorMessage, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { syncUserGigs } from "../_shared/sync_gigs.ts";

async function hmacHex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payload),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

/// Hex digests are case-insensitive; the comparison above is not. Normalising
/// both sides means a provider that ever emits uppercase does not silently 401
/// every delivery and stop imports with no visible cause.
function normalizeHex(value: string): string {
  return value.trim().toLowerCase();
}

/// How far back a single event makes us look.
///
/// A `gigs.added` for one trip used to trigger a download of the driver's
/// entire history. A busy driver generating dozens of events a shift produced
/// dozens of full history downloads, which is how this hits Argyle's rate
/// limits and the function's wall-clock budget. A window comfortably wider than
/// any plausible delivery delay costs nothing and bounds the work.
const INCREMENTAL_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const secret = Deno.env.get("ARGYLE_WEBHOOK_SECRET");
  if (!secret) {
    // Not echoed to the caller: telling an unauthenticated prober that the
    // secret is unset is telling them the door is open.
    console.error("ARGYLE_WEBHOOK_SECRET is not configured");
    return jsonResponse({ error: "Webhook unavailable" }, 503);
  }

  // The signature is computed over the raw body, read before parsing — any
  // re-serialisation would change the bytes and break verification.
  const payload = await req.text();
  const received = normalizeHex(req.headers.get("X-Argyle-Signature") ?? "");
  const expected = normalizeHex(await hmacHex(secret, payload));
  if (!constantTimeEqual(received, expected)) {
    return jsonResponse({ error: "Invalid signature" }, 401);
  }

  let event: {
    id?: string;
    event?: string;
    data?: { user?: string };
  };
  try {
    event = JSON.parse(payload);
  } catch {
    // Signed but unparseable. Retrying will not fix it, so 400 rather than 500
    // stops the provider re-delivering it forever.
    return jsonResponse({ error: "Malformed payload" }, 400);
  }

  const argyleUserId = event.data?.user;
  if (!argyleUserId) return jsonResponse({ accepted: true });

  try {
    const db = serviceClient();

    // Idempotency. A valid request can be replayed indefinitely, and the
    // provider itself retries on any non-2xx — each replay previously kicked
    // off another sync. Recording the event id first means a duplicate is
    // rejected by the unique constraint before any work happens.
    if (event.id) {
      const { error: seenError } = await db
        .from("webhook_events")
        .insert({ provider: "argyle", event_id: event.id });
      // 23505 is unique_violation: already handled, nothing more to do.
      if (seenError?.code === "23505") {
        return jsonResponse({ accepted: true, duplicate: true });
      }
      if (seenError) throw seenError;
    }

    const { data: connection, error } = await db
      .from("income_connections")
      .select("user_id")
      .eq("argyle_user_id", argyleUserId)
      .maybeSingle();
    if (error) throw error;
    // 200, not an error: an unknown user is a permanent condition and retrying
    // it forever helps nobody.
    if (!connection) return jsonResponse({ accepted: true });

    const shouldSync = event.event?.startsWith("gigs.") ||
      event.event === "accounts.added" ||
      event.event === "accounts.updated";
    if (shouldSync) {
      await syncUserGigs(db, connection.user_id, argyleUserId, {
        // `accounts.added` is a first connection, so it has to look at
        // everything. Ongoing gig events only need the recent window.
        updatedAfter: event.event === "accounts.added"
          ? undefined
          : new Date(Date.now() - INCREMENTAL_WINDOW_MS).toISOString(),
      });
    }
    return jsonResponse({ accepted: true });
  } catch (error) {
    // Logged in full, reported vaguely: the raw text carries Postgres and
    // upstream API detail that an unauthenticated caller should not see. 500
    // is correct here — these are transient, and a retry may well succeed.
    console.error("argyle-webhook failed", errorMessage(error));
    return jsonResponse({ error: "Sync failed" }, 500);
  }
});
