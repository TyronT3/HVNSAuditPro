import { corsHeadersFor, jsonResponse } from "../_shared/cors.ts";
import { getCallerProfile, MANAGER_ROLES } from "../_shared/auth.ts";
import { getGreatSoftToken, greatSoftFetch } from "../_shared/greatsoftClient.ts";

Deno.serve(async (req) => {
  const cors = corsHeadersFor(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405, cors);

  const caller = await getCallerProfile(req);
  if (caller.error) return jsonResponse({ error: caller.error.message }, caller.error.status, cors);
  if (!MANAGER_ROLES.includes(caller.profile.role)) {
    return jsonResponse({ error: "Insufficient role" }, 403, cors);
  }

  try {
    await getGreatSoftToken();
    const info = await greatSoftFetch("/api/Info");

    return jsonResponse({
      ok: info.ok,
      message: info.ok
        ? "GreatSoft token and API connection succeeded."
        : "GreatSoft token succeeded, but API info call failed.",
      status: info.status,
      info: info.body,
    }, info.ok ? 200 : 502, cors);
  } catch (error) {
    return jsonResponse({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }, 500, cors);
  }
});
