-- Review against the live catalog and restore-tested backup before production use.
-- Keep BUSINESS_ACCESS_ENABLED=false until migration, admin allowlist and tests pass.
begin;
create table public.business_access_admins (
 email text primary key check (email=lower(btrim(email)))
);
revoke all on public.business_access_admins from public,anon,authenticated,service_role;
grant select,insert,delete on public.business_access_admins to service_role;
alter table public.business_access_admins enable row level security;

alter table public.businesses alter column owner_id drop not null;
alter table public.businesses add column created_by uuid references public.profiles(id) on delete set null;
alter table public.businesses add column ownership_review_required boolean not null default true;
-- Never guess historical creators or intended owners. Preserve all current links.
create table public.business_members (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 role text not null check(role in ('owner','manager')),
 status text not null default 'active' check(status in ('active','inactive')),
 assigned_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(business_id,user_id)
);
create unique index business_one_active_owner on public.business_members(business_id) where role='owner' and status='active';
create index business_member_user on public.business_members(user_id,status,business_id);
insert into public.business_members(business_id,user_id,role)
 select id,owner_id,'owner' from public.businesses where owner_id is not null;
-- Per-creator request keys make retried wizard submissions safe after a lost response.
create table public.business_creation_requests (
 actor_user_id uuid not null, request_id uuid not null, payload_hash text not null,
 business_id uuid, created_at timestamptz not null default now(),
 primary key(actor_user_id,request_id)
);
alter table public.business_creation_requests enable row level security;
revoke all on public.business_creation_requests from public,anon,authenticated,service_role;
grant select,insert,update on public.business_creation_requests to authenticated;

create table public.business_user_lookup_rate (
 actor_user_id uuid not null, window_start timestamptz not null, attempts integer not null,
 primary key(actor_user_id,window_start)
);
alter table public.business_user_lookup_rate enable row level security;
revoke all on public.business_user_lookup_rate from public,anon,authenticated,service_role;

create table public.business_invitations (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 invited_email text not null check(invited_email=lower(btrim(invited_email))),
 invited_by uuid references public.profiles(id) on delete set null,
 token_hash text not null unique check(token_hash ~ '^[a-f0-9]{64}$'),
 status text not null default 'pending' check(status in ('pending','accepted','revoked','expired')),
 expires_at timestamptz not null, accepted_at timestamptz,
 delivery_status text not null default 'pending' check(delivery_status in ('pending','sent','failed')),
 created_at timestamptz not null default now()
);
create unique index business_pending_invitation on public.business_invitations(business_id,invited_email) where status='pending';
create table public.business_access_logs (
 id uuid primary key default gen_random_uuid(), business_id uuid not null,
 actor_user_id uuid, target_user_id uuid, action text not null,
 details jsonb not null default '{}', created_at timestamptz not null default now()
);
create index business_access_history on public.business_access_logs(business_id,created_at desc,id);
-- Keep business content when an account is deleted; require explicit reassignment first.
do $$ declare c record; begin
 for c in select conname from pg_constraint where conrelid='public.businesses'::regclass and contype='f'
 and conkey=array[(select attnum from pg_attribute where attrelid='public.businesses'::regclass and attname='owner_id')]::smallint[] loop
 execute format('alter table public.businesses drop constraint %I',c.conname);
 end loop;
end $$;
alter table public.businesses add constraint businesses_primary_owner_fk foreign key(owner_id) references public.profiles(id) on delete restrict;

create function public.business_actor() returns uuid language sql stable security definer set search_path='' as $$
 select u.id from auth.users u join public.auth_sessions s on s.user_id=u.id
 where u.id=auth.uid() and s.id=nullif(auth.jwt()->>'session_id','')::uuid
 and s.revoked_at is null and s.expires_at>now()
 and (u.banned_until is null or u.banned_until<=now())
$$;
create function public.business_is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u join public.business_access_admins a on a.email=lower(u.email)
 where u.id=public.business_actor() and u.email_confirmed_at is not null)
$$;
create function public.business_role(p_business uuid) returns text language sql stable security definer set search_path='' as $$
 select m.role from public.business_members m where m.business_id=p_business and m.user_id=public.business_actor() and m.status='active'
$$;
create function public.business_can_manage(p_business uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.business_is_admin() or public.business_role(p_business) is not null
$$;
create function public.business_can_access_team(p_business uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.business_is_admin() or coalesce(public.business_role(p_business)='owner',false)
$$;

-- Verify owner eligibility at the database boundary as well as in the API.
create function public.business_assignable_account(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select (public.business_is_admin() or p_user=public.business_actor()) and exists (
  select 1 from auth.users u join public.profiles p on p.id=u.id
  where u.id=p_user and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=now())
 )
$$;
revoke all on function public.business_assignable_account(uuid) from public,anon,authenticated;
grant execute on function public.business_assignable_account(uuid) to authenticated;


create policy business_creation_requests_self on public.business_creation_requests for all to authenticated
 using(actor_user_id=public.business_actor()) with check(actor_user_id=public.business_actor());

-- All ownership writes synchronize the single owner membership in the same transaction.
create function public.business_sync_owner() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='UPDATE' and new.owner_id is not distinct from old.owner_id then return new; end if;
 update public.business_members set status='inactive',updated_at=now()
 where business_id=new.id and role='owner' and status='active';
 if new.owner_id is not null then
 insert into public.business_members(business_id,user_id,role,status,assigned_by)
 values(new.id,new.owner_id,'owner','active',public.business_actor())
 on conflict(business_id,user_id) do update set role='owner',status='active',assigned_by=excluded.assigned_by,updated_at=now();
 end if;
 if TG_OP='INSERT' then
 insert into public.business_access_logs(business_id,actor_user_id,target_user_id,action)
 values(new.id,public.business_actor(),new.owner_id,case when new.owner_id is null then 'create_unassigned' else 'create_owner' end);
 end if;
 return new;
end $$;
create trigger business_sync_owner after insert or update of owner_id on public.businesses for each row execute function public.business_sync_owner();
create function public.business_member_invariant() returns trigger language plpgsql security definer set search_path='' as $$
declare bid uuid; oid uuid; owners integer; matching integer;
begin
 bid:=coalesce(new.business_id,old.business_id);
 select owner_id into oid from public.businesses where id=bid;
 if not found then return null; end if;
 select count(*),count(*) filter(where user_id=oid) into owners,matching from public.business_members where business_id=bid and role='owner' and status='active';
 if (oid is null and owners<>0) or (oid is not null and (owners<>1 or matching<>1)) then
 raise exception 'Owner membership invariant violated' using errcode='23514'; end if;
 return null;
end $$;
create constraint trigger business_member_invariant after insert or update or delete on public.business_members
 deferrable initially deferred for each row execute function public.business_member_invariant();

-- Block arbitrary ownership/creator/package edits, including direct PostgREST requests.
create function public.business_protect_fields() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') then
 if public.business_actor() is null then raise exception 'Session required' using errcode='42501'; end if;
 if TG_OP='INSERT' then
 if not public.business_is_admin() and new.owner_id is distinct from public.business_actor() then raise exception 'Invalid owner' using errcode='42501'; end if;
 if new.owner_id is not null and not public.business_assignable_account(new.owner_id) then raise exception 'Select an active verified owner' using errcode='22023'; end if;
 new.created_by:=public.business_actor(); new.ownership_review_required:=false;
 if not public.business_is_admin() and (new.is_verified or new.plan_id<>'basic') then raise exception 'Protected business fields' using errcode='42501'; end if;
 elsif not public.business_can_manage(old.id) then
 raise exception 'Business access denied' using errcode='42501';
 elsif new.id is distinct from old.id or new.created_at is distinct from old.created_at or new.profile_views is distinct from old.profile_views
 or coalesce(new.details->'stats','{}'::jsonb) is distinct from coalesce(old.details->'stats','{}'::jsonb)
 or new.owner_id is distinct from old.owner_id or new.created_by is distinct from old.created_by
 or new.ownership_review_required is distinct from old.ownership_review_required
 or (not public.business_is_admin() and (new.plan_id is distinct from old.plan_id or new.is_verified is distinct from old.is_verified)) then
 raise exception 'Use the authorized access operation' using errcode='42501';
 end if;
 end if;
 return new;
end $$;
create trigger business_protect_fields before insert or update on public.businesses for each row execute function public.business_protect_fields();
create function public.business_protect_delete() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') and not public.business_can_access_team(old.id) then
  raise exception 'Business access denied' using errcode='42501';
 end if;
 return old;
end $$;
revoke all on function public.business_protect_delete() from public,anon,authenticated;
create trigger business_protect_delete before delete on public.businesses for each row execute function public.business_protect_delete();

create function public.business_change_access(p_business uuid,p_action text,p_target uuid,p_expected_owner uuid,
 p_previous_owner text,p_pending_invitations text) returns void language plpgsql security definer set search_path='' as $$
declare b public.businesses; actor uuid:=public.business_actor();
begin
 select * into b from public.businesses where id=p_business for update;
 if not found or actor is null or not public.business_can_access_team(p_business) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_action not in ('assign_owner','transfer_owner','add_manager','remove_manager') then raise exception 'Invalid action' using errcode='22023'; end if;
 if p_action in ('assign_owner','add_manager') and not public.business_is_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if p_action<>'remove_manager' and not exists(select 1 from auth.users u join public.profiles p on p.id=u.id where u.id=p_target and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=now())) then
 raise exception 'Select an active verified account' using errcode='22023'; end if;
 if p_action in ('assign_owner','transfer_owner') then
 if b.owner_id is distinct from p_expected_owner or (p_action='assign_owner' and b.owner_id is not null) or (p_action='transfer_owner' and b.owner_id is null) or b.owner_id=p_target then
 raise exception 'Ownership changed; reload before confirming' using errcode='40001'; end if;
 if p_previous_owner is null or p_previous_owner not in ('remove','manager') or p_pending_invitations is null or p_pending_invitations not in ('revoke','keep') then raise exception 'Choose transfer outcomes' using errcode='22023'; end if;
 update public.businesses set owner_id=p_target,ownership_review_required=false,updated_at=now() where id=p_business;
 if b.owner_id is not null and p_previous_owner='manager' then
 update public.business_members set role='manager',status='active',assigned_by=actor,updated_at=now() where business_id=p_business and user_id=b.owner_id;
 end if;
 if p_pending_invitations='revoke' then
  with revoked as (update public.business_invitations set status='revoked' where business_id=p_business and status='pending' returning id)
  insert into public.business_access_logs(business_id,actor_user_id,action,details)
  select p_business,actor,'revoke_invitation',jsonb_build_object('invitation_id',id,'reason','ownership_transfer') from revoked;
 end if;
 -- An owner must never later accept a pending manager invitation for this business.
 with revoked as (update public.business_invitations set status='revoked' where business_id=p_business and status='pending' and invited_email=(select lower(email) from auth.users where id=p_target) returning id)
 insert into public.business_access_logs(business_id,actor_user_id,target_user_id,action,details)
 select p_business,actor,p_target,'revoke_invitation',jsonb_build_object('invitation_id',id,'reason','owner_assigned') from revoked;
 elsif p_action='add_manager' then
 if b.owner_id=p_target then raise exception 'This account is already the Owner' using errcode='22023'; end if;
 insert into public.business_members(business_id,user_id,role,status,assigned_by) values(p_business,p_target,'manager','active',actor)
 on conflict(business_id,user_id) do update set role='manager',status='active',assigned_by=actor,updated_at=now();
 with revoked as (update public.business_invitations set status='revoked' where business_id=p_business and status='pending' and invited_email=(select lower(email) from auth.users where id=p_target) returning id)
 insert into public.business_access_logs(business_id,actor_user_id,target_user_id,action,details)
 select p_business,actor,p_target,'revoke_invitation',jsonb_build_object('invitation_id',id,'reason','manager_assigned') from revoked;
 else
 update public.business_members set status='inactive',updated_at=now() where business_id=p_business and user_id=p_target and role='manager' and status='active';
 if not found then raise exception 'Active Manager not found' using errcode='22023'; end if;
 end if;
 insert into public.business_access_logs(business_id,actor_user_id,target_user_id,action,details)
 values(p_business,actor,p_target,p_action,
  case when p_action in ('assign_owner','transfer_owner') then
   jsonb_build_object('previous_owner',b.owner_id,'new_owner',p_target,'previous_owner_access',p_previous_owner,'pending_invitations',p_pending_invitations)
  else '{}'::jsonb end);
end $$;

create function public.business_find_user(p_business uuid,p_email text) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=public.business_actor(); attempts integer;
begin
 if actor is null or (not public.business_is_admin() and (p_business is null or not public.business_can_access_team(p_business))) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid email' using errcode='22023'; end if;
 delete from public.business_user_lookup_rate where actor_user_id=actor and window_start<now()-interval '1 day';
 insert into public.business_user_lookup_rate(actor_user_id,window_start,attempts) values(actor,date_trunc('minute',now()),1)
 on conflict(actor_user_id,window_start) do update set attempts=business_user_lookup_rate.attempts+1 returning business_user_lookup_rate.attempts into attempts;
 if attempts>30 then raise exception 'Too many account searches. Try again shortly.' using errcode='P4290'; end if;
 return (select jsonb_build_object('id',u.id,'name',p.full_name,'email',u.email,'verified',u.email_confirmed_at is not null)
 from auth.users u join public.profiles p on p.id=u.id where lower(u.email)=lower(btrim(p_email)) and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=now()) limit 1);
end $$;
create function public.business_access_details(p_business uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.business_can_access_team(p_business) then raise exception 'Access denied' using errcode='42501'; end if;
 return jsonb_build_object(
 'business',(select jsonb_build_object('id',b.id,'name',b.business_name,'status',b.status,'created_by',b.created_by,
 'created_by_name',coalesce(nullif(cp.full_name,''),cu.email,b.created_by::text),'created_at',b.created_at,'review_required',b.ownership_review_required)
 from public.businesses b left join public.profiles cp on cp.id=b.created_by left join auth.users cu on cu.id=b.created_by where b.id=p_business),
 'owner',(select jsonb_build_object('id',u.id,'name',p.full_name,'email',u.email) from public.businesses b join auth.users u on u.id=b.owner_id join public.profiles p on p.id=u.id where b.id=p_business),
 'managers',coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'name',p.full_name,'email',u.email,'status',m.status)) from public.business_members m join auth.users u on u.id=m.user_id join public.profiles p on p.id=u.id where m.business_id=p_business and m.role='manager' and m.status='active'),'[]'),
 'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',id,'email',invited_email,'expires_at',expires_at,'status',case when expires_at<=now() then 'expired' else status end,'delivery_status',delivery_status)) from public.business_invitations where business_id=p_business and status='pending'),'[]'),
 'history',coalesce((select jsonb_agg(to_jsonb(h)) from (
 select l.id,l.actor_user_id,l.target_user_id,l.action,l.details,l.created_at,
 coalesce(nullif(ap.full_name,''),au.email,l.actor_user_id::text) as actor_name,
 coalesce(nullif(op.full_name,''),ou.email,l.details->>'previous_owner') as previous_owner_name,
 coalesce(nullif(np.full_name,''),nu.email,l.details->>'new_owner') as new_owner_name
 from public.business_access_logs l
 left join public.profiles ap on ap.id=l.actor_user_id left join auth.users au on au.id=l.actor_user_id
 left join public.profiles op on op.id=nullif(l.details->>'previous_owner','')::uuid left join auth.users ou on ou.id=op.id
 left join public.profiles np on np.id=nullif(l.details->>'new_owner','')::uuid left join auth.users nu on nu.id=np.id
 where l.business_id=p_business order by l.created_at desc,l.id desc limit 100) h),'[]'));
end $$;

create function public.business_invite(p_business uuid,p_email text,p_hash text,p_days integer) returns uuid language plpgsql security definer set search_path='' as $$
declare invitation uuid; actor uuid:=public.business_actor();
begin
 perform 1 from public.businesses where id=p_business for update;
 if not found or not public.business_can_access_team(p_business) then raise exception 'Access denied' using errcode='42501'; end if;
 p_email:=lower(btrim(p_email));
 if p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or p_days is null or p_days<1 or p_days>30 then raise exception 'Invalid invitation' using errcode='22023'; end if;
 if exists(select 1 from public.business_members m join auth.users u on u.id=m.user_id where m.business_id=p_business and m.status='active' and lower(u.email)=p_email) then raise exception 'Account already has access' using errcode='23505'; end if;
 with expired as (update public.business_invitations set status='expired' where business_id=p_business and status='pending' and expires_at<=now() returning id)
 insert into public.business_access_logs(business_id,actor_user_id,action,details)
 select p_business,actor,'expire_invitation',jsonb_build_object('invitation_id',id) from expired;
 insert into public.business_invitations(business_id,invited_email,invited_by,token_hash,expires_at) values(p_business,p_email,actor,p_hash,now()+make_interval(days=>p_days)) returning id into invitation;
 insert into public.business_access_logs(business_id,actor_user_id,action,details) values(p_business,actor,'invite',jsonb_build_object('invitation_id',invitation));
 return invitation;
end $$;
create function public.business_revoke_invitation(p_business uuid,p_invitation uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.businesses where id=p_business for update;
 if not public.business_can_access_team(p_business) then raise exception 'Access denied' using errcode='42501'; end if;
 update public.business_invitations set status='revoked' where id=p_invitation and business_id=p_business and status='pending';
 if not found then raise exception 'Pending invitation not found' using errcode='22023'; end if;
 insert into public.business_access_logs(business_id,actor_user_id,action,details) values(p_business,public.business_actor(),'revoke_invitation',jsonb_build_object('invitation_id',p_invitation));
end $$;
create function public.business_accept_invitation(p_hash text) returns uuid language plpgsql security definer set search_path='' as $$
declare inv public.business_invitations; bid uuid; actor uuid:=public.business_actor(); verified_email text;
begin
 select business_id into bid from public.business_invitations where token_hash=p_hash;
 perform 1 from public.businesses where id=bid for update;
 select * into inv from public.business_invitations where token_hash=p_hash for update;
 select lower(email) into verified_email from auth.users where id=actor and email_confirmed_at is not null;
 if actor is null or verified_email is null or inv.id is null or inv.status<>'pending' or inv.expires_at<=now() or inv.invited_email<>verified_email then raise exception 'Invitation is invalid, expired or belongs to another account' using errcode='42501'; end if;
 if exists(select 1 from public.business_members where business_id=bid and user_id=actor and status='active') then raise exception 'Account already has access' using errcode='23505'; end if;
 insert into public.business_members(business_id,user_id,role,status,assigned_by) values(bid,actor,'manager','active',inv.invited_by)
 on conflict(business_id,user_id) do update set role='manager',status='active',assigned_by=excluded.assigned_by,updated_at=now();
 update public.business_invitations set status='accepted',accepted_at=now() where id=inv.id;
 insert into public.business_access_logs(business_id,actor_user_id,target_user_id,action,details) values(bid,actor,actor,'accept_invitation',jsonb_build_object('invitation_id',inv.id));
 return bid;
end $$;

alter table public.business_members enable row level security;
alter table public.business_invitations enable row level security;
alter table public.business_access_logs enable row level security;
revoke all on public.business_members,public.business_invitations,public.business_access_logs from public,anon,authenticated,service_role;
grant select on public.business_members,public.business_access_logs to authenticated;
-- Tokens and invitee emails are only returned through owner-scoped RPC projections.
create policy business_members_private on public.business_members for select to authenticated using (user_id=public.business_actor() or public.business_can_access_team(business_id));
create policy business_history_private on public.business_access_logs for select to authenticated using (public.business_can_access_team(business_id));
grant select,update on public.business_invitations to service_role;
grant select on public.business_members,public.business_access_logs to service_role;

-- Content writes use caller JWTs, never a service-role fallback when enabled.
create policy business_member_read on public.businesses for select to authenticated using(owner_id=public.business_actor() or public.business_can_manage(id));
create policy business_member_update on public.businesses for update to authenticated using(public.business_can_manage(id)) with check(public.business_can_manage(id));
create policy business_account_create on public.businesses for insert to authenticated with check(public.business_actor() is not null and (owner_id=public.business_actor() or public.business_is_admin()));
create policy business_delete_owner on public.businesses for delete to authenticated using(public.business_can_access_team(id));
-- Restrictive gates constrain older permissive owner policies, including expired sessions.
create policy business_write_update_gate on public.businesses as restrictive for update to authenticated using(public.business_can_manage(id)) with check(public.business_can_manage(id));
create policy business_write_insert_gate on public.businesses as restrictive for insert to authenticated with check(public.business_actor() is not null and (owner_id=public.business_actor() or public.business_is_admin()));
create policy business_write_delete_gate on public.businesses as restrictive for delete to authenticated using(public.business_can_access_team(id));

do $$ declare t text; begin
 foreach t in array array['products','services','events','offers','gallery_photos','business_people','business_section_visibility'] loop
 execute format('create policy business_member_content on public.%I for all to authenticated using(public.business_can_manage(business_id)) with check(public.business_can_manage(business_id))',t);
 execute format('create policy business_content_insert_gate on public.%I as restrictive for insert to authenticated with check(public.business_can_manage(business_id))',t);
 execute format('create policy business_content_update_gate on public.%I as restrictive for update to authenticated using(public.business_can_manage(business_id)) with check(public.business_can_manage(business_id))',t);
 execute format('create policy business_content_delete_gate on public.%I as restrictive for delete to authenticated using(public.business_can_manage(business_id))',t);
 execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 end loop;
end $$;
grant select,insert,update,delete on public.businesses to authenticated;
-- Extend the existing restrictive publication rules without changing public behavior.
do $$ declare t text; p record; begin
 foreach t in array array['products','services'] loop
 for p in select policyname,qual from pg_policies where schemaname='public' and tablename=t and permissive='RESTRICTIVE' and cmd='SELECT' loop
 execute format('alter policy %I on public.%I using ((%s) or public.business_can_manage(business_id))',p.policyname,t,p.qual);
 end loop; end loop;
end $$;

-- Explicit grants; PostgreSQL grants PUBLIC execution by default.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('business_actor','business_is_admin','business_role','business_can_manage','business_can_access_team','business_sync_owner','business_member_invariant','business_protect_fields','business_change_access','business_find_user','business_access_details','business_invite','business_revoke_invitation','business_accept_invitation') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 if f.proname not in ('business_sync_owner','business_member_invariant','business_protect_fields') then execute format('grant execute on function %s to authenticated',f.signature); end if;
 -- Anonymous public content policies invoke this helper; it returns false without a session.
 if f.proname='business_can_manage' then execute format('grant execute on function %s to anon',f.signature); end if;
 end loop;
end $$;
-- Atomic business, owner membership, creation audit and optional leadership rows.
-- The invoker's RLS and all existing triggers still apply.
create function public.business_create_with_people(p_business jsonb,p_people jsonb default '[]'::jsonb,p_request_id uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare columns_sql text; values_sql text; result jsonb; person jsonb; owner_id uuid; actor uuid:=public.business_actor(); fingerprint text; previous_hash text; previous_business uuid;
 allowed constant text[]:=array['owner_id','business_name','business_name_mr','slug','global_category_id',
 'category','category_mr','owner_name_mr','designation_mr','tagline_mr','description','description_mr',
 'logo_url','logo_public_id','profile_image_url','profile_image_public_id','phone','whatsapp_number',
 'address','social_links','status','is_verified','plan_id','is_published','details'];
 allowed_person constant text[]:=array['full_name_en','full_name_mr','designation_en','designation_mr','description_en','description_mr',
 'profile_image_url','profile_image_public_id','display_order','is_primary','is_active'];
begin
 if public.business_actor() is null then raise exception 'Session required' using errcode='42501'; end if;
 if jsonb_typeof(p_business) is distinct from 'object' or jsonb_typeof(p_people) is distinct from 'array' or jsonb_array_length(p_people)>50 then
  raise exception 'Invalid business creation payload' using errcode='22023'; end if;
 if exists(select 1 from jsonb_object_keys(p_business) key where not key=any(allowed)) then
  raise exception 'Invalid business fields' using errcode='22023'; end if;
 if not p_business ?& array['business_name','slug','owner_id'] then raise exception 'Business name, slug, and owner are required' using errcode='22023'; end if;
 owner_id:=nullif(p_business->>'owner_id','')::uuid;
 if owner_id is not null and not public.business_assignable_account(owner_id) then raise exception 'Select an active verified owner' using errcode='22023'; end if;
 if p_request_id is not null then
  fingerprint:=md5(((p_business-'slug') #- '{details,slug}' #- '{details,id}' #- '{details,createdAt}')::text || p_people::text);
  perform pg_advisory_xact_lock(hashtextextended(actor::text || p_request_id::text,0));
  select payload_hash,business_id into previous_hash,previous_business from public.business_creation_requests
   where actor_user_id=actor and request_id=p_request_id for update;
  if found then
   if previous_hash<>fingerprint then raise exception 'Creation request was already used for different details' using errcode='40001'; end if;
   if previous_business is not null then
    select to_jsonb(b) into result from public.businesses b where b.id=previous_business and b.created_by=actor and public.business_can_manage(b.id);
    if result is null then raise exception 'The previous creation is unavailable' using errcode='40001'; end if;
    return result;
   end if;
  else
   insert into public.business_creation_requests(actor_user_id,request_id,payload_hash) values(actor,p_request_id,fingerprint);
  end if;
 end if;
 if exists(select 1 from jsonb_array_elements(p_people) item where jsonb_typeof(item) is distinct from 'object') then
  raise exception 'Invalid business person' using errcode='22023'; end if;
 for person in select * from jsonb_array_elements(p_people) loop
  if exists(select 1 from jsonb_object_keys(person) key where not key=any(allowed_person)) or nullif(btrim(person->>'full_name_en'),'') is null then
   raise exception 'Invalid business person' using errcode='22023'; end if;
 end loop;
 if (select count(*) from jsonb_array_elements(p_people) item where coalesce((item->>'is_active')::boolean,true))>0
 and (select count(*) from jsonb_array_elements(p_people) item where coalesce((item->>'is_active')::boolean,true) and coalesce((item->>'is_primary')::boolean,false))<>1 then
  raise exception 'Exactly one active primary person is required' using errcode='22023'; end if;
 select string_agg(format('%I',key),',' order by key),string_agg(format('r.%I',key),',' order by key)
 into columns_sql,values_sql from jsonb_object_keys(p_business) key;
 execute format('insert into public.businesses (%s) select %s from jsonb_populate_record(null::public.businesses,$1) r returning to_jsonb(businesses)',columns_sql,values_sql)
 into result using p_business;
 insert into public.business_people (business_id,full_name_en,full_name_mr,designation_en,designation_mr,description_en,description_mr,
 profile_image_url,profile_image_public_id,display_order,is_primary,is_active)
 select (result->>'id')::uuid,p.full_name_en,p.full_name_mr,p.designation_en,p.designation_mr,p.description_en,p.description_mr,
 p.profile_image_url,p.profile_image_public_id,coalesce(p.display_order,0),coalesce(p.is_primary,false),coalesce(p.is_active,true)
 from jsonb_to_recordset(p_people) as p(full_name_en text,full_name_mr text,designation_en text,designation_mr text,description_en text,description_mr text,
 profile_image_url text,profile_image_public_id text,display_order integer,is_primary boolean,is_active boolean);
 if p_request_id is not null then update public.business_creation_requests set business_id=(result->>'id')::uuid where actor_user_id=actor and request_id=p_request_id; end if;
 return result;
end $$;
revoke all on function public.business_create_with_people(jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.business_create_with_people(jsonb,jsonb,uuid) to authenticated;

-- Serialize member content writes with transfer/removal. Re-check after the lock.
create function public.business_lock_content() returns trigger language plpgsql security definer set search_path='' as $$
declare bid uuid;
begin
 if current_setting('role',true) not in ('authenticated','anon') then return coalesce(new,old); end if;
 bid:=case when TG_OP='DELETE' then old.business_id else new.business_id end;
 if TG_OP='UPDATE' and old.business_id is distinct from new.business_id then raise exception 'Content cannot change business' using errcode='42501'; end if;
 perform 1 from public.businesses where id=bid for update;
 if not found or not public.business_can_manage(bid) then raise exception 'Business access denied' using errcode='42501'; end if;
 return coalesce(new,old);
end $$;
revoke all on function public.business_lock_content() from public,anon,authenticated;
do $$ declare t text; begin
 foreach t in array array['products','services','events','offers','gallery_photos','business_people','business_section_visibility'] loop
 execute format('create trigger business_lock_content before insert or update or delete on public.%I for each row execute function public.business_lock_content()',t);
 end loop;
end $$;
create policy business_private_read_gate on public.businesses as restrictive for select to authenticated
 using(is_published or owner_id=public.business_actor() or public.business_can_manage(id));
-- Existing permissive owner policies must not leak inactive content to revoked sessions.
do $$ declare t text; begin
 foreach t in array array['products','services','events','offers','gallery_photos','business_people','business_section_visibility'] loop
 execute format('create policy business_private_content_gate on public.%I as restrictive for select to authenticated using(public.business_can_manage(business_id) or (exists(select 1 from public.businesses b where b.id=business_id and b.is_published) and coalesce((to_jsonb(%I)->>''is_active'')::boolean,true) and coalesce((to_jsonb(%I)->>''is_published'')::boolean,true) and to_jsonb(%I)->>''deleted_at'' is null))',t,t,t,t);
 end loop;
end $$;
create function public.business_my_invitations() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'businessName',b.business_name,'expiresAt',i.expires_at)),'[]')
 from public.business_invitations i join public.businesses b on b.id=i.business_id
 join auth.users u on lower(u.email)=i.invited_email
 where u.id=public.business_actor() and u.email_confirmed_at is not null and i.status='pending' and i.expires_at>now()
$$;
revoke all on function public.business_my_invitations() from public,anon,authenticated;
grant execute on function public.business_my_invitations() to authenticated;

do $$ begin
 if to_regprocedure('public.move_category_items(uuid,text,uuid[],uuid)') is not null then
 if (select prosecdef from pg_proc where oid='public.move_category_items(uuid,text,uuid[],uuid)'::regprocedure) then raise exception 'Review move_category_items security before migration'; end if;
 grant execute on function public.move_category_items(uuid,text,uuid[],uuid) to authenticated;
 end if;
end $$;
commit;
