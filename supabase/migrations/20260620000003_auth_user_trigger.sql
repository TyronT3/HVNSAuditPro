-- Auto-create a public.users profile row when a Supabase Auth user is created.
-- Ensures public.users.id always equals auth.uid(), which is required by RLS policies.
-- Without this trigger, the in-app "Add User" modal could insert a row with a random UUID,
-- causing the new user's login to fail (profile fetch returns 0 rows under RLS).

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, role, active, full_name)
  values (
    new.id,
    new.email,
    'staff',
    false,
    split_part(new.email, '@', 1)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_auth_user();

-- Enforce unique emails so the modal can look up profiles by email reliably.
create unique index if not exists users_email_uq on public.users(email);
