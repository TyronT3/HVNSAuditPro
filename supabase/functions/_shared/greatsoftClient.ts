type GreatSoftConfig = {
  baseUrl: string;
  tokenUrl: string;
  clientId: string;
  clientSecret: string;
  scope: string;
};

type GreatSoftToken = {
  access_token: string;
  token_type?: string;
  expires_in?: number;
};

export type TimeTranPayload = {
  TranDate: string;
  TimeStartUTC: string;
  TaskID: string;
  ActOvhID: string;
  WIPHrQty: number;
  StdRateID?: string;
  Narration?: string;
};

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function getConfig(): GreatSoftConfig {
  return {
    baseUrl: env("GREATSOFT_BASE_URL").replace(/\/$/, ""),
    tokenUrl: env("GREATSOFT_TOKEN_URL"),
    clientId: env("GREATSOFT_CLIENT_ID"),
    clientSecret: env("GREATSOFT_CLIENT_SECRET"),
    scope: Deno.env.get("GREATSOFT_SCOPE") || "INT.Payroll PM.Time PM.Read",
  };
}

async function readJsonOrText(res: Response): Promise<unknown> {
  const text = await res.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

let cachedToken: { token: string; expiresAt: number } | null = null;

export async function getGreatSoftToken(): Promise<string> {
  if (cachedToken && Date.now() < cachedToken.expiresAt - 60_000) {
    return cachedToken.token;
  }

  const cfg = getConfig();
  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: cfg.clientId,
    client_secret: cfg.clientSecret,
    scope: cfg.scope,
  });

  const res = await fetch(cfg.tokenUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json",
    },
    body,
  });

  const parsed = await readJsonOrText(res);
  if (!res.ok) {
    throw new Error(`GreatSoft token request failed (${res.status}): ${JSON.stringify(parsed)}`);
  }

  const token = parsed as GreatSoftToken;
  if (!token.access_token) {
    throw new Error("GreatSoft token response did not include access_token");
  }

  const ttlSeconds = Math.max(120, Number(token.expires_in) || 300);
  cachedToken = {
    token: token.access_token,
    expiresAt: Date.now() + ttlSeconds * 1000,
  };

  return token.access_token;
}

export async function greatSoftFetch(path: string, init: RequestInit = {}): Promise<{
  ok: boolean;
  status: number;
  body: unknown;
}> {
  const cfg = getConfig();
  const token = await getGreatSoftToken();
  const res = await fetch(`${cfg.baseUrl}${path}`, {
    ...init,
    headers: {
      "Accept": "application/json",
      "Content-Type": "application/json",
      "Authorization": `Bearer ${token}`,
      ...(init.headers || {}),
    },
  });

  return {
    ok: res.ok,
    status: res.status,
    body: await readJsonOrText(res),
  };
}

export async function getStdRateId(taskId: string, actOvhId: string, tranDate: string): Promise<string | undefined> {
  const qs = new URLSearchParams({
    taskID: taskId,
    actID: actOvhId,
    tranDate,
  });
  const res = await greatSoftFetch(`/api/V2/TsLookup/RateList?${qs.toString()}`);
  if (!res.ok) return undefined;

  const rows = Array.isArray(res.body) ? res.body : [];
  const first = rows[0] as Record<string, unknown> | undefined;
  const id = first?.StdRateID || first?.StdRateId || first?.stdRateID || first?.id;
  return typeof id === "string" ? id : undefined;
}

export async function createTimeTran(payload: TimeTranPayload): Promise<{
  ok: boolean;
  status: number;
  body: unknown;
}> {
  return await greatSoftFetch("/api/V2/Timesheet/TimeTran", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

