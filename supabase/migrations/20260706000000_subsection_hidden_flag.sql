-- Lets an assignee dismiss a preset subsection with 0 hours allocated/logged
-- from their "My Work" list without deleting it. Managers can restore it
-- from the Edit Audit screen. Purely additive, no RLS policy changes needed:
-- the existing subsections UPDATE policy already lets the assignee update
-- their own row.
alter table public.subsections
  add column if not exists hidden_from_worklist boolean not null default false;
