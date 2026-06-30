import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders, jsonResponse } from '../_shared/cors.ts'

// Warn when actual hours reach this fraction of budget.
const BUDGET_WARN_PCT = 0.8

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders })

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const today = new Date().toISOString().slice(0, 10)

  // ── 1. Overdue subsections ────────────────────────────────────────────────
  const { data: overdueRaw, error: overdueErr } = await supabase
    .from('subsections')
    .select('id, name, due_date, step, assignee_email, sections(name, audits(name, client))')
    .neq('step', 'Signed Off')
    .lt('due_date', today)
    .not('due_date', 'is', null)
    .not('assignee_email', 'is', null)

  if (overdueErr) return jsonResponse({ error: overdueErr.message }, 500)

  // Group overdue items by assignee email for per-person digest emails.
  const overdueByAssignee: Record<string, object[]> = {}
  for (const item of (overdueRaw ?? [])) {
    const email = item.assignee_email as string
    if (!overdueByAssignee[email]) overdueByAssignee[email] = []
    overdueByAssignee[email].push({
      id: item.id,
      name: item.name,
      due_date: item.due_date,
      step: item.step,
      audit_name: (item.sections as any)?.audits?.name ?? '',
      audit_client: (item.sections as any)?.audits?.client ?? '',
      section_name: (item.sections as any)?.name ?? '',
    })
  }

  // ── 2. Budget status ──────────────────────────────────────────────────────
  const { data: summaries, error: sumErr } = await supabase
    .from('audit_summary')
    .select('id, name, client, type, budget_hours, actual_hours')
    .gt('budget_hours', 0)

  if (sumErr) return jsonResponse({ error: sumErr.message }, 500)

  const nearBudget: object[] = []
  const overBudget: object[] = []

  for (const a of (summaries ?? [])) {
    const pct = parseFloat(a.actual_hours) / parseFloat(a.budget_hours)
    const entry = { id: a.id, name: a.name, client: a.client, type: a.type,
                    budget_hours: a.budget_hours, actual_hours: a.actual_hours,
                    pct: Math.round(pct * 100) }
    if (pct >= 1.0)              overBudget.push(entry)
    else if (pct >= BUDGET_WARN_PCT) nearBudget.push(entry)
  }

  // ── 3. Alert recipients (directors + managers) ────────────────────────────
  const { data: recipients } = await supabase
    .from('users')
    .select('email, full_name, role')
    .in('role', ['director', 'manager'])
    .eq('active', true)

  // ── 4. Build payload ──────────────────────────────────────────────────────
  // This payload is the contract for the Resend integration step.
  // When emails are added: iterate overdueByAssignee for per-person digests,
  // and send nearBudget/overBudget summary to each alertRecipient.
  const payload = {
    generatedAt: new Date().toISOString(),
    overdue: {
      totalCount: (overdueRaw ?? []).length,
      byAssignee: overdueByAssignee,
    },
    budget: {
      nearBudget,
      overBudget,
      alertRecipients: (recipients ?? []).map(r => ({
        email: r.email,
        name: r.full_name,
        role: r.role,
      })),
    },
    emailsQueued: 0, // will become actual count once Resend is wired up
  }

  // ── 5. Log the run ────────────────────────────────────────────────────────
  await supabase.from('notification_log').insert({
    overdue_count:      (overdueRaw ?? []).length,
    near_budget_count:  nearBudget.length,
    over_budget_count:  overBudget.length,
    payload,
    emails_sent:        false,
  })

  return jsonResponse(payload)
})
