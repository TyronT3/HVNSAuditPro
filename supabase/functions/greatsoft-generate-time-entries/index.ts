import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createTimeTran, getStdRateId, TimeTranPayload } from "../_shared/greatsoftClient.ts";

type RequestBody = {
  weekEnding?: string;
  auditId?: string;
  dryRun?: boolean;
  includeAllStaff?: boolean;
};

type UserProfile = {
  id: string;
  email: string;
  role: string;
  active: boolean;
  greatsoft_emp_id?: string | null;
  greatsoft_sync_enabled?: boolean | null;
};

function startOfWeekFromFriday(weekEnding: string): { start: string; end: string } {
  const end = new Date(`${weekEnding}T00:00:00.000Z`);
  const start = new Date(end);
  start.setUTCDate(start.getUTCDate() - 6);
  return {
    start: start.toISOString(),
    end: new Date(`${weekEnding}T23:59:59.999Z`).toISOString(),
  };
}

function dateOnly(iso: string): string {
  return new Date(iso).toISOString().slice(0, 10);
}

function buildNarration(row: any): string {
  const auditName = row.subsections?.sections?.audits?.name || "Audit";
  const sectionName = row.subsections?.sections?.name || "Section";
  const subName = row.subsections?.name || "Activity";
  const note = row.note ? ` - ${row.note}` : "";
  return `HVNSAuditPro: ${auditName} / ${sectionName} / ${subName}${note}`;
}

function getEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Missing Authorization header" }, 401);

    const supabaseUrl = getEnv("SUPABASE_URL");
    const anonKey = getEnv("SUPABASE_ANON_KEY");
    const serviceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const adminClient = createClient(supabaseUrl, serviceKey);

    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return jsonResponse({ error: "Invalid user session" }, 401);

    const { data: profile, error: profileError } = await adminClient
      .from("users")
      .select("id,email,role,active,greatsoft_emp_id,greatsoft_sync_enabled")
      .eq("id", authData.user.id)
      .single();

    const userProfile = profile as UserProfile | null;

    if (profileError || !userProfile || !userProfile.active) {
      return jsonResponse({ error: "Active user profile not found" }, 403);
    }

    const body = await req.json().catch(() => ({})) as RequestBody;
    const dryRun = body.dryRun !== false;
    const pushEnabled = Deno.env.get("GREATSOFT_PUSH_ENABLED") === "true";
    const isManager = userProfile.role === "manager" || userProfile.role === "director";
    const includeAllStaff = Boolean(body.includeAllStaff && isManager);

    if (!body.weekEnding) {
      return jsonResponse({ error: "weekEnding is required in YYYY-MM-DD format" }, 400);
    }

    if (!dryRun && !pushEnabled) {
      return jsonResponse({
        error: "Actual GreatSoft pushes are disabled. Set GREATSOFT_PUSH_ENABLED=true after dry-run testing.",
      }, 403);
    }

    const { start, end } = startOfWeekFromFriday(body.weekEnding);

    let query = adminClient
      .from("step_logs")
      .select(`
        id,
        subsection_id,
        step,
        hours,
        logged_at,
        logged_by,
        logged_by_email,
        note,
        subsections (
          id,
          name,
          greatsoft_act_ovh_id,
          greatsoft_activity_code,
          greatsoft_activity_name,
          sections (
            id,
            name,
            greatsoft_task_id,
            greatsoft_task_code,
            greatsoft_task_name,
            audits (
              id,
              name,
              greatsoft_client_code,
              greatsoft_client_name
            )
          )
        )
      `)
      .gt("hours", 0)
      .gte("logged_at", start)
      .lte("logged_at", end);

    if (!includeAllStaff) query = query.eq("logged_by", userProfile.id);

    const { data: logs, error: logsError } = await query;
    if (logsError) return jsonResponse({ error: logsError.message }, 500);

    const filteredLogs = body.auditId
      ? (logs || []).filter((row: any) => row.subsections?.sections?.audits?.id === body.auditId)
      : (logs || []);

    if (!filteredLogs.length) {
      return jsonResponse({
        ok: true,
        dryRun,
        weekEnding: body.weekEnding,
        count: 0,
        results: [],
      });
    }

    const { data: existing, error: pushError } = await adminClient
      .from("greatsoft_time_pushes")
      .select("step_log_id,status,greatsoft_wip_tran_det_id")
      .in("step_log_id", filteredLogs.map((row: any) => row.id));

    if (pushError) return jsonResponse({ error: pushError.message }, 500);

    const existingByStepLog = new Map((existing || []).map((row: any) => [row.step_log_id, row]));
    const results = [];

    for (const row of filteredLogs) {
      const prior = existingByStepLog.get(row.id);
      if (prior?.status === "pushed") {
        results.push({
          stepLogId: row.id,
          status: "skipped",
          reason: "Already pushed",
          greatsoftWipTranDetId: prior.greatsoft_wip_tran_det_id,
        });
        continue;
      }

      const section = row.subsections?.sections;
      const audit = section?.audits;
      const missing = [];
      if (!audit?.greatsoft_client_code) missing.push("audit.greatsoft_client_code");
      if (!section?.greatsoft_task_id) missing.push("section.greatsoft_task_id");
      if (!row.subsections?.greatsoft_act_ovh_id) missing.push("subsection.greatsoft_act_ovh_id");

      if (missing.length) {
        results.push({
          stepLogId: row.id,
          status: "needs_mapping",
          missing,
          audit: audit?.name,
          section: section?.name,
          subsection: row.subsections?.name,
          hours: Number(row.hours || 0),
        });
        continue;
      }

      const tranDate = dateOnly(row.logged_at);
      const payload: TimeTranPayload = {
        TranDate: `${tranDate}T00:00:00`,
        TimeStartUTC: new Date(row.logged_at).toISOString(),
        TaskID: section.greatsoft_task_id,
        ActOvhID: row.subsections.greatsoft_act_ovh_id,
        WIPHrQty: Number(row.hours || 0),
        Narration: buildNarration(row),
      };

      if (!dryRun) {
        const stdRateId = await getStdRateId(payload.TaskID, payload.ActOvhID, tranDate);
        if (stdRateId) payload.StdRateID = stdRateId;
      }

      if (dryRun) {
        results.push({
          stepLogId: row.id,
          status: "dry_run",
          payload,
          audit: audit.name,
          section: section.name,
          subsection: row.subsections.name,
        });
        continue;
      }

      const created = await createTimeTran(payload);
      const response = created.body as Record<string, unknown> | null;
      const wipId = typeof response?.WIPTranDetID === "string"
        ? response.WIPTranDetID
        : typeof response?.wipTranDetID === "string"
          ? response.wipTranDetID
          : null;

      await adminClient
        .from("greatsoft_time_pushes")
        .upsert({
          step_log_id: row.id,
          submitted_by: row.logged_by,
          submitted_by_email: row.logged_by_email,
          greatsoft_wip_tran_det_id: wipId,
          status: created.ok ? "pushed" : "failed",
          request_payload: payload,
          response_payload: created.body,
          error_message: created.ok ? null : `GreatSoft returned HTTP ${created.status}`,
          pushed_at: created.ok ? new Date().toISOString() : null,
        }, { onConflict: "step_log_id" });

      results.push({
        stepLogId: row.id,
        status: created.ok ? "pushed" : "failed",
        httpStatus: created.status,
        greatsoftWipTranDetId: wipId,
        response: created.body,
      });
    }

    return jsonResponse({
      ok: true,
      dryRun,
      weekEnding: body.weekEnding,
      count: results.length,
      results,
    });
  } catch (error) {
    return jsonResponse({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});
