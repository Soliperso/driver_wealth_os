type JsonRecord = Record<string, unknown>;

export type ArgyleUserResponse = {
  id: string;
  user_token?: string;
};

export type ArgyleTokenResponse = {
  user_token: string;
};

export type ArgyleGig = {
  id: string;
  account: string;
  employer?: string;
  updated_at?: string;
  status?: string;
  type?: string;
  earning_type?: string;
  start_datetime?: string;
  end_datetime?: string;
  duration?: number;
  distance?: string;
  distance_unit?: string;
  income?: {
    currency?: string;
    total?: string;
    total_charge?: string;
    customer_price?: string;
    fees?: string;
    tips?: string;
    bonus?: string;
  };
};

type ArgylePage<T> = {
  results?: T[];
  next?: string | null;
};

export function argyleEnvironment(): "sandbox" | "production" {
  return Deno.env.get("ARGYLE_ENV") === "production"
    ? "production"
    : "sandbox";
}

function baseUrl(): string {
  return argyleEnvironment() === "production"
    ? "https://api.argyle.com/v2"
    : "https://api-sandbox.argyle.com/v2";
}

function credentials(): string {
  const id = Deno.env.get("ARGYLE_API_KEY_ID");
  const secret = Deno.env.get("ARGYLE_API_KEY_SECRET");
  if (!id || !secret) throw new Error("Argyle credentials are not configured");
  return btoa(`${id}:${secret}`);
}

export async function argyleRequest<T>(
  pathOrUrl: string,
  init: RequestInit = {},
): Promise<T> {
  const url = pathOrUrl.startsWith("https://")
    ? pathOrUrl
    : `${baseUrl()}${pathOrUrl}`;
  if (!url.startsWith(baseUrl())) throw new Error("Invalid Argyle page URL");

  const response = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Basic ${credentials()}`,
      "Content-Type": "application/json",
      ...init.headers,
    },
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Argyle request failed (${response.status}): ${detail}`);
  }
  return await response.json() as T;
}

export async function listAllGigs(argyleUserId: string): Promise<ArgyleGig[]> {
  const gigs: ArgyleGig[] = [];
  let next: string | null = `/gigs?user=${encodeURIComponent(argyleUserId)}&limit=200`;
  while (next) {
    const page: ArgylePage<ArgyleGig> = await argyleRequest(next);
    gigs.push(...(page.results ?? []));
    next = page.next ?? null;
  }
  return gigs;
}

export function safeSourceMetadata(gig: ArgyleGig): JsonRecord {
  return {
    gig_type: gig.type ?? null,
    earning_type: gig.earning_type ?? null,
    source_status: gig.status ?? null,
  };
}
