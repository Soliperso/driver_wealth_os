import type { SupabaseClient } from "@supabase/supabase-js";

import {
  type ArgyleGig,
  listAllGigs,
  safeSourceMetadata,
} from "./argyle.ts";

function amount(value?: string): number | null {
  if (value == null) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function miles(gig: ArgyleGig): number | null {
  const distance = amount(gig.distance);
  if (distance == null) return null;
  return gig.distance_unit === "km" ? distance * 0.621371 : distance;
}

function providerKey(name: string): string {
  return name.toLowerCase().replaceAll(/[^a-z0-9]+/g, "_").replaceAll(/^_|_$/g, "");
}

export async function syncUserGigs(
  db: SupabaseClient,
  userId: string,
  argyleUserId: string,
): Promise<number> {
  const { data: job, error: jobError } = await db
    .from("sync_jobs")
    .insert({ user_id: userId, status: "running" })
    .select("id")
    .single();
  if (jobError) throw jobError;

  try {
    const gigs = await listAllGigs(argyleUserId);
    const accounts = new Map<string, { provider: string; displayName: string; category: string }>();
    for (const gig of gigs) {
      const displayName = gig.employer?.trim() || "Connected platform";
      accounts.set(gig.account, {
        provider: providerKey(displayName) || "other",
        displayName,
        category: gig.type ?? "gig",
      });
    }

    const accountIds = new Map<string, string>();
    for (const [externalAccountId, account] of accounts) {
      const { data, error } = await db
        .from("work_accounts")
        .upsert({
          user_id: userId,
          external_account_id: externalAccountId,
          provider: account.provider,
          display_name: account.displayName,
          category: account.category,
          status: "connected",
          last_synced_at: new Date().toISOString(),
        }, { onConflict: "user_id,external_account_id" })
        .select("id")
        .single();
      if (error) throw error;
      accountIds.set(externalAccountId, data.id);
    }

    if (gigs.length > 0) {
      const records = gigs.map((gig) => {
        const displayName = gig.employer?.trim() || "Connected platform";
        return {
          user_id: userId,
          work_account_id: accountIds.get(gig.account),
          source_kind: "gig",
          external_id: gig.id,
          provider: providerKey(displayName) || "other",
          status: gig.status ?? "completed",
          earning_type: gig.earning_type ?? null,
          currency: gig.income?.currency ?? "USD",
          earnings_amount: amount(gig.income?.total) ?? 0,
          customer_price: amount(gig.income?.customer_price),
          platform_fees: amount(gig.income?.fees),
          tips: amount(gig.income?.tips),
          bonus: amount(gig.income?.bonus),
          duration_hours: gig.duration == null ? null : gig.duration / 3600,
          distance_miles: miles(gig),
          started_at: gig.start_datetime ?? null,
          ended_at: gig.end_datetime ?? null,
          source_updated_at: gig.updated_at ?? null,
          source_metadata: safeSourceMetadata(gig),
        };
      });
      const { error } = await db
        .from("earnings_entries")
        .upsert(records, { onConflict: "user_id,source_kind,external_id" });
      if (error) throw error;
    }

    await db.from("sync_jobs").update({
      status: "succeeded",
      records_processed: gigs.length,
      finished_at: new Date().toISOString(),
    }).eq("id", job.id);
    return gigs.length;
  } catch (error) {
    await db.from("sync_jobs").update({
      status: "failed",
      error_message: error instanceof Error ? error.message.slice(0, 1000) : "Unexpected error",
      finished_at: new Date().toISOString(),
    }).eq("id", job.id);
    throw error;
  }
}
