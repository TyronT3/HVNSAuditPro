-- Add freetext comment/note field to subsections.
-- Additive only — nullable, no default, no impact on existing rows or queries.
-- Covered by existing subsections UPDATE RLS policies (managers + assignees can update).

alter table public.subsections add column if not exists comment text;
