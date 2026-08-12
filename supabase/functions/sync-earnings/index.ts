import "@supabase/functions-js/edge-runtime.d.ts";

import { errorMessage, jsonResponse } from "../_shared/http.ts";
import { requireUserId, serviceClient } from "../_shared/supabase.ts";
import { syncUserGigs } from "../_shared/sync_gigs.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const userId = await requireUserId(req);
    const db = serviceClient();
    const { data: connection, error } = await db
      .from("income_connections")
      .select("argyle_user_id")
      .eq("user_id", userId)
      .single();
    if (error || !connection) return jsonResponse({ error: "No income connection" }, 409);

    const recordsProcessed = await syncUserGigs(
      db,
      userId,
      connection.argyle_user_id,
    );
    return jsonResponse({ recordsProcessed });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error) }, 500);
  }
});
