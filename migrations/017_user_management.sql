-- Run after 015. No password material is copied out of Supabase Auth.
begin;
create table public.user_management_audit (
 id uuid primary key default gen_random_uuid(), actor_id uuid, target_id uuid,
 action text not null, outcome text not null check(outcome in ('requested','success','failed','rejected')),
 created_at timestamptz not null default now()
);
create index on public.user_management_audit(target_id, created_at desc);
alter table public.user_management_audit enable row level security;
revoke all on public.user_management_audit from anon, authenticated;
grant select, insert on public.user_management_audit to service_role;

-- Trigger runs in the same transaction as provider changes, including revocation.
create function public.audit_auth_account() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if TG_OP = 'INSERT' then
  insert into public.user_management_audit(actor_id,target_id,action,outcome)
   values(nullif(new.raw_app_meta_data->>'created_by','')::uuid,new.id,'user_created','success');
 else
  if new.encrypted_password is distinct from old.encrypted_password then
   update public.auth_sessions set revoked_at = now() where user_id=new.id and revoked_at is null;
   insert into public.user_management_audit(actor_id,target_id,action,outcome) values(new.id,new.id,'password_changed','success');
  end if;
  if new.banned_until is distinct from old.banned_until then
   update public.auth_sessions set revoked_at = now() where user_id=new.id and revoked_at is null;
   insert into public.user_management_audit(target_id,action,outcome) values(new.id,'account_status_changed','success');
  end if;
 end if;
 return new;
end $$;
revoke all on function public.audit_auth_account() from public, anon, authenticated;
create trigger audit_auth_account after insert or update on auth.users for each row execute function public.audit_auth_account();

-- Service-only projection: never expose auth.users or its private fields through REST.
create function public.management_users(admin_emails text[], search_text text default '', role_filter text default '', status_filter text default '', date_from timestamptz default null, date_to timestamptz default null, sort_key text default 'created_at', descending boolean default true, page_number integer default 1, target uuid default null)
returns jsonb language sql stable security definer set search_path = '' as $$
 with accounts as (
 select u.id, coalesce(p.full_name,u.raw_user_meta_data->>'full_name','') full_name,u.email,
 case when lower(u.email)=any(admin_emails) then 'admin' else 'user' end role,
 case when u.banned_until > now() then 'inactive' else 'active' end status,
 u.created_at,u.last_sign_in_at last_login,
 u.raw_app_meta_data->>'created_by' created_by,
 u.email_confirmed_at is not null email_verified
 from auth.users u left join public.profiles p on p.id=u.id
 ), filtered as (
 select * from accounts where (target is null or id=target)
 and (search_text='' or position(lower(search_text) in lower(full_name||' '||coalesce(email,'')||' '||id::text))>0)
 and (role_filter='' or role=role_filter) and(status_filter='' or status=status_filter)
 and(date_from is null or created_at>=date_from) and(date_to is null or created_at<date_to)
 ), paged as (
 select * from filtered order by
 case when not descending and sort_key='name' then lower(full_name) end asc,
 case when descending and sort_key='name' then lower(full_name) end desc,
 case when not descending and sort_key='created_at' then created_at end asc,
 case when descending and sort_key='created_at' then created_at end desc,
 case when not descending and sort_key='last_login' then last_login end asc nulls last,
 case when descending and sort_key='last_login' then last_login end desc nulls last,id
 limit 25 offset (greatest(1,least(page_number,1000000))-1)*25
 ) select jsonb_build_object('users',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]'::jsonb),
 'total',(select count(*) from filtered),'summary',(select jsonb_build_object('total',count(*),'active',count(*) filter(where status='active'),'inactive',count(*) filter(where status='inactive'),'this_month',count(*) filter(where created_at>=date_trunc('month',now()))) from accounts));
$$;
revoke all on function public.management_users(text[],text,text,text,timestamptz,timestamptz,text,boolean,integer,uuid) from public,anon,authenticated;
grant execute on function public.management_users(text[],text,text,text,timestamptz,timestamptz,text,boolean,integer,uuid) to service_role;

create function public.management_update_profile(actor uuid,target uuid,new_name text) returns void language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,full_name) values(target,new_name) on conflict(id) do update set full_name=excluded.full_name;
 insert into public.user_management_audit(actor_id,target_id,action,outcome) values(actor,target,'profile_updated','success');
end $$;
revoke all on function public.management_update_profile(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.management_update_profile(uuid,uuid,text) to service_role;
commit;
