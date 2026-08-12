import "@supabase/functions-js/edge-runtime.d.ts";

import {
  argyleEnvironment,
  argyleRequest,
  type ArgyleTokenResponse,
  type ArgyleUserResponse,
} from "../_shared/argyle.ts";
import { errorMessage, jsonResponse } from "../_shared/http.ts";
import { requireUserId, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const userId = await requireUserId(req);
    const db = serviceClient();
    const { platform } = await req.json().catch(() => ({ platform: null }));
    if (platform != null && (typeof platform !== "string" || platform.length > 64)) {
      return jsonResponse({ error: "Invalid platform" }, 400);
    }

    const { data: existing, error: lookupError } = await db
      .from("income_connections")
      .select("argyle_user_id")
      .eq("user_id", userId)
      .maybeSingle();
    if (lookupError) throw lookupError;

    let argyleUserId = existing?.argyle_user_id as string | undefined;
    let userToken: string;
    if (!argyleUserId) {
      const created = await argyleRequest<ArgyleUserResponse>("/users", {
        method: "POST",
        body: JSON.stringify({
          external_id: userId,
          external_metadata: { app: "driver_wealth_os" },
        }),
      });
      argyleUserId = created.id;
      userToken = created.user_token ?? "";
      const { error } = await db.from("income_connections").upsert({
        user_id: userId,
        argyle_user_id: argyleUserId,
        environment: argyleEnvironment(),
      });
      if (error) throw error;
    } else {
      userToken = "";
    }

    if (!userToken) {
      const token = await argyleRequest<ArgyleTokenResponse>("/user-tokens", {
        method: "POST",
        body: JSON.stringify({ user: argyleUserId }),
      });
      userToken = token.user_token;
    }

    return jsonResponse({
      userToken,
      sandbox: argyleEnvironment() === "sandbox",
      requestedPlatform: platform ?? null,
    });
  } catch (error) {
    const message = errorMessage(error);
    const status = message.includes("Authentication") || message.includes("session") ? 401 : 500;
    return jsonResponse({ error: message }, status);
  }
});
