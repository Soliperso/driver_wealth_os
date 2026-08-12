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

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const secret = Deno.env.get("ARGYLE_WEBHOOK_SECRET");
    if (!secret) throw new Error("Webhook secret is not configured");
    const payload = await req.text();
    const received = req.headers.get("X-Argyle-Signature") ?? "";
    const expected = await hmacHex(secret, payload);
    if (!constantTimeEqual(received, expected)) {
      return jsonResponse({ error: "Invalid signature" }, 401);
    }

    const event = JSON.parse(payload) as {
      event?: string;
      data?: { user?: string };
    };
    const argyleUserId = event.data?.user;
    if (!argyleUserId) return jsonResponse({ accepted: true });

    const db = serviceClient();
    const { data: connection, error } = await db
      .from("income_connections")
      .select("user_id")
      .eq("argyle_user_id", argyleUserId)
      .maybeSingle();
    if (error) throw error;
    if (!connection) return jsonResponse({ accepted: true });

    const shouldSync = event.event?.startsWith("gigs.") ||
      event.event === "accounts.added" ||
      event.event === "accounts.updated";
    if (shouldSync) {
      await syncUserGigs(db, connection.user_id, argyleUserId);
    }
    return jsonResponse({ accepted: true });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error) }, 500);
  }
});
