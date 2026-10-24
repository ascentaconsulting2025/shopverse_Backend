-- Run before deploying the persistent authentication backend.
create table if not exists public.auth_sessions (
  id uuid primary key references auth.sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  revoked_at timestamptz
);
alter table public.auth_sessions enable row level security;
revoke all on public.auth_sessions from anon, authenticated;
grant all on public.auth_sessions to service_role;
create index if not exists auth_sessions_user_idx on public.auth_sessions(user_id);
