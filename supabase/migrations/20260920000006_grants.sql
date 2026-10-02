-- The Iron Yard — table privileges
--
-- RLS filters rows, but only *after* the role holds the table privilege. A
-- table with perfect policies and no GRANT returns "permission denied", not an
-- empty set.
--
-- Hosted Supabase grants these to anon/authenticated by default for tables in
-- `public`, so this migration is usually a no-op there. It is declared anyway
-- so the schema is self-contained: a restore into a fresh database, or a
-- project where the default privileges were tightened, still works.
--
-- These grants are safe precisely because every table has RLS enabled and
-- forced (see 20260920000004_rls.sql) — the policies decide which rows a
-- caller actually sees.

grant usage on schema public to anon, authenticated;

-- Signed-in users: row access is decided by the policies.
grant select, insert, update, delete
  on all tables in schema public
  to authenticated;

-- Anonymous users get nothing. Every table requires auth.uid(), and a signed-
-- out caller has none, so granting anon access would only produce confusing
-- empty results instead of a clear authentication error.
revoke all on all tables in schema public from anon;

-- Sequences (none today, but future identity columns need this).
grant usage, select on all sequences in schema public to authenticated;

-- Same privileges for tables added by later migrations.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;

alter default privileges in schema public
  grant usage, select on sequences to authenticated;

-- ---------------------------------------------------------------------------
-- Function execution
-- ---------------------------------------------------------------------------
-- The role helpers are SECURITY DEFINER and read only the caller's own row;
-- they are referenced by policies, which execute as the caller.
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_staff() to authenticated;
grant execute on function public.current_role_name() to authenticated;
grant execute on function public.trainer_has_member(uuid) to authenticated;

-- Admin-only maintenance: not exposed to clients. Call it from a scheduled
-- job or the SQL editor.
revoke all on function public.expire_memberships() from public, anon, authenticated;
