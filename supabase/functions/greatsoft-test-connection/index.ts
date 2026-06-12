import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { getGreatSoftToken, greatSoftFetch } from "../_shared/greatsoftClient.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

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
    }, info.ok ? 200 : 502);
  } catch (error) {
    return jsonResponse({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});

