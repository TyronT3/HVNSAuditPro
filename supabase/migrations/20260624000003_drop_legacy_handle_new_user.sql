-- Drop legacy handle_new_user function, superseded by handle_new_auth_user.
--
-- handle_new_user predates the migration system and has three problems:
--   1. Missing set search_path (search_path injection vector)
--   2. Doesn't set active=false (new users would be immediately active)
--   3. Reads role from raw_user_meta_data (user could set their own role at signup)
--
-- handle_new_auth_user (wired to on_auth_user_created trigger since migration
-- 20260620000003) supersedes it: has set search_path, forces active=false,
-- always assigns role='staff'.
--
-- CASCADE drops any trigger still pointing at handle_new_user. The correct
-- trigger (on_auth_user_created -> handle_new_auth_user) is unaffected.

drop function if exists public.handle_new_user() cascade;
