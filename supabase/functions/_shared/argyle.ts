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

/// A malformed or self-referential `next` cursor would otherwise spin here
/// until the function is killed by the platform, having done nothing. 200 pages
/// at 200 rows is 40,000 gigs — years of full-time driving.
const MAX_GIG_PAGES = 200;

export async function listAllGigs(
  argyleUserId: string,
  options: { updatedAfter?: string } = {},
): Promise<ArgyleGig[]> {
  const gigs: ArgyleGig[] = [];
  const params = new URLSearchParams({
    user: argyleUserId,
    limit: "200",
  });
  // An incremental window turns a single-trip webhook into a small request
  // instead of a full re-download of the driver's entire history.
  if (options.updatedAfter) params.set("updated_at__gte", options.updatedAfter);

  let next: string | null = `/gigs?${params.toString()}`;
  const seen = new Set<string>();
  for (let page = 0; page < MAX_GIG_PAGES; page++) {
    const url: string | null = next;
    if (url === null) break;
    // A cursor that points back at a page already fetched is a loop.
    if (seen.has(url)) break;
    seen.add(url);
    const body: ArgylePage<ArgyleGig> = await argyleRequest(url);
    gigs.push(...(body.results ?? []));
    next = body.next ?? null;
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
