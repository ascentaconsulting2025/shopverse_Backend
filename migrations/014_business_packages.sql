-- Apply after 001-013. Transactional, rerunnable; never deletes existing content.
begin;
lock table public.businesses, public.products, public.services, public.events,
  public.offers, public.gallery_photos in share row exclusive mode;

-- The authoritative package matrix. NULL limit means enabled with no quota.
create table if not exists public.business_package_rules (
  plan_id text primary key,
  capabilities jsonb not null
);
insert into public.business_package_rules values
 ('basic', '{"products":0,"services":0,"gallery":20,"events":5,"offers":0,"themes":false,"verificationViews":null}'),
 ('standard', '{"products":20,"services":20,"gallery":20,"events":5,"offers":0,"themes":false,"verificationViews":10000}'),
 ('premium', '{"products":20,"services":20,"gallery":20,"events":5,"offers":null,"themes":true,"verificationViews":0}')
on conflict (plan_id) do update set capabilities = excluded.capabilities;
-- Legacy "free" has no independent entitlement; normalize to Basic. Unknown plans fail closed.
update public.businesses set plan_id = 'basic' where plan_id not in ('basic','standard','premium');
alter table public.businesses alter column plan_id set default 'basic';
alter table public.businesses drop constraint if exists businesses_package_fk;
alter table public.businesses add constraint businesses_package_fk foreign key (plan_id) references public.business_package_rules(plan_id);
alter table public.businesses add column if not exists profile_views bigint not null default 0 check (profile_views >= 0);

create table if not exists public.business_package_usage (
 business_id uuid not null references public.businesses(id) on delete cascade,
 resource text not null check (resource in ('products','services','gallery','events','offers')),
 used integer not null default 0 check (used >= 0), primary key (business_id,resource)
);
insert into public.business_package_usage(business_id,resource,used)
select b.id, r.resource, case r.resource
 when 'products' then (select count(*) from public.products p where p.business_id=b.id)
 when 'services' then (select count(*) from public.services p where p.business_id=b.id)
 when 'gallery' then (select count(*) from public.gallery_photos p where p.business_id=b.id and p.is_active and p.deleted_at is null)
 when 'events' then (select count(*) from public.events p where p.business_id=b.id and p.is_active and p.deleted_at is null)
 when 'offers' then (select count(*) from public.offers p where p.business_id=b.id and p.is_active and p.deleted_at is null) end
from public.businesses b cross join (values ('products'),('services'),('gallery'),('events'),('offers')) r(resource)
on conflict (business_id,resource) do update set used=excluded.used;

-- Direct Supabase writes must not bypass the trusted Express authorization path.
-- All writes use the service-role backend, which checks business ownership/admin status.
revoke insert, update, delete on public.businesses, public.products, public.services,
 public.events, public.offers, public.gallery_photos, public.business_categories,
 public.business_section_visibility from anon, authenticated;

alter table public.business_package_rules enable row level security;
alter table public.business_package_usage enable row level security;
revoke all on public.business_package_rules, public.business_package_usage from public, anon, authenticated;
grant select on public.business_package_rules, public.business_package_usage to service_role;

-- Shared database enforcement covers inserts, bulk inserts, restores and publication
-- transitions, including writes through future routes and service-role SQL/RPCs.
create or replace function public.enforce_business_package_content() returns trigger
language plpgsql security definer set search_path=public as $$
declare
 v_resource text := case when tg_table_name='gallery_photos' then 'gallery' else tg_table_name end;
 business uuid; caps jsonb; quota integer; before_counted boolean := false;
 after_counted boolean := false; publish_transition boolean := false; delta integer;
 old_row jsonb; new_row jsonb;
begin
 if tg_op <> 'INSERT' then old_row:=to_jsonb(old); end if;
 if tg_op <> 'DELETE' then new_row:=to_jsonb(new); end if;
 business:=coalesce((new_row->>'business_id')::uuid,(old_row->>'business_id')::uuid);
 if tg_op='UPDATE' and new.business_id <> old.business_id then
   raise exception 'Moving content between businesses is not supported';
 end if;
 -- Serializes quota changes with package activation/downgrade for this business.
 perform 1 from public.businesses where id=business for update;
 if not found and tg_op='DELETE' then return old; end if; -- parent cascade
 select r.capabilities into caps from public.businesses b join public.business_package_rules r using(plan_id) where b.id=business;
 if caps is null then raise exception 'Business package is unavailable'; end if;
 quota:=(caps->>v_resource)::integer;
 if v_resource in ('products','services') then
   before_counted:=tg_op <> 'INSERT'; after_counted:=tg_op <> 'DELETE';
   publish_transition:=tg_op='UPDATE' and not coalesce((old_row->>'is_published')::boolean,true)
      and coalesce((new_row->>'is_published')::boolean,true);
 else
   before_counted:=tg_op <> 'INSERT' and coalesce((old_row->>'is_active')::boolean,true) and old_row->>'deleted_at' is null;
   after_counted:=tg_op <> 'DELETE' and coalesce((new_row->>'is_active')::boolean,true) and new_row->>'deleted_at' is null;
   publish_transition:=after_counted and not before_counted;
 end if;
 if quota=0 and (tg_op='INSERT' or publish_transition) then
   raise exception '% requires %', initcap(v_resource), case when v_resource='offers' then 'Premium' else 'Standard or Premium' end;
 end if;
 -- A move out of a hidden folder is also a publication transition.
 if tg_op='UPDATE' and v_resource in ('products','services')
    and new_row->>'folder_category_id' is distinct from old_row->>'folder_category_id'
    and coalesce((new_row->>'is_published')::boolean,true)
    and exists(select 1 from public.business_categories c where c.id=(old_row->>'folder_category_id')::uuid and not c.is_published)
    and (new_row->>'folder_category_id' is null or exists(select 1 from public.business_categories c where c.id=(new_row->>'folder_category_id')::uuid and c.is_published))
    and quota=0 then raise exception '% requires Standard or Premium',initcap(v_resource); end if;
 delta:=after_counted::integer-before_counted::integer;
 insert into public.business_package_usage(business_id,resource,used) values(business,v_resource,0) on conflict do nothing;
 if delta > 0 then
   update public.business_package_usage u set used=used+delta
     where u.business_id=business and u.resource=v_resource
       and (quota is null or used+delta <= quota);
   if not found then raise exception '% limit reached (maximum %)',initcap(v_resource),quota; end if;
 elsif delta < 0 then
   update public.business_package_usage u set used=greatest(0,used+delta)
    where u.business_id=business and u.resource=v_resource;
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;

do $$ declare t text; begin
 foreach t in array array['products','services','gallery_photos','events','offers'] loop
   execute format('drop trigger if exists enforce_package on public.%I',t);
   execute format('create trigger enforce_package before insert or update or delete on public.%I for each row execute function public.enforce_business_package_content()',t);
 end loop;
end $$;

-- Re-enabling a hidden folder/section/profile must not republish excluded content.
create or replace function public.enforce_business_package_publication() returns trigger
language plpgsql security definer set search_path=public as $$
declare caps jsonb; business uuid; begin
 business:=case when tg_table_name='businesses' then (to_jsonb(new)->>'id')::uuid else (to_jsonb(new)->>'business_id')::uuid end;
 perform 1 from public.businesses where id=business for update;
 select r.capabilities into caps from public.businesses b join public.business_package_rules r using(plan_id) where b.id=business;
 if tg_table_name='businesses' then select capabilities into caps from public.business_package_rules where plan_id=new.plan_id; end if;
 if tg_table_name='business_categories' then
   if new.is_published and not old.is_published and (caps->>(new.type||'s'))::integer=0 then
     raise exception '% requires Standard or Premium',initcap(new.type||'s');
   end if;
 elsif tg_table_name='business_section_visibility' then
   if new.products and not old.products and (caps->>'products')::integer=0 and exists(select 1 from products where business_id=business and is_published) then raise exception 'Products requires Standard or Premium'; end if;
   if new.services and not old.services and (caps->>'services')::integer=0 and exists(select 1 from services where business_id=business and is_published) then raise exception 'Services requires Standard or Premium'; end if;
   if new.special_offers and not old.special_offers and (caps->>'offers')::integer=0 and exists(select 1 from offers where business_id=business and is_active and deleted_at is null) then raise exception 'Offers requires Premium'; end if;
 elsif new.is_published and not old.is_published then
   if (caps->>'products')::integer=0 and exists(select 1 from products where business_id=business and is_published) then raise exception 'Products requires Standard or Premium'; end if;
   if (caps->>'services')::integer=0 and exists(select 1 from services where business_id=business and is_published) then raise exception 'Services requires Standard or Premium'; end if;
   if (caps->>'offers')::integer=0 and exists(select 1 from offers where business_id=business and is_active and deleted_at is null) then raise exception 'Offers requires Premium'; end if;
 end if;
 return new;
end $$;
do $$ declare t text; begin
 foreach t in array array['businesses','business_categories','business_section_visibility'] loop
  execute format('drop trigger if exists enforce_package_publication on public.%I',t);
  execute format('create trigger enforce_package_publication before update on public.%I for each row execute function public.enforce_business_package_publication()',t);
 end loop;
end $$;
revoke all on function public.enforce_business_package_publication() from public,anon,authenticated;

-- Reuse is_verified (the same state used by the administrative verification click).
-- No downgrade or unrelated edit revokes a manual or package-granted badge.
create or replace function public.apply_business_package() returns trigger
language plpgsql security definer set search_path=public as $$
declare caps jsonb; threshold bigint; begin
 select capabilities into caps from public.business_package_rules where plan_id=new.plan_id;
 threshold:=(caps->>'verificationViews')::bigint;
 if threshold is not null and new.profile_views >= threshold then new.is_verified:=true; end if;
 if tg_op='INSERT' and caps->>'themes' <> 'true' and
   (coalesce(new.details->'themeConfig','null'::jsonb) <> 'null'::jsonb
    or coalesce(new.details->'themeDraft','null'::jsonb) <> 'null'::jsonb
    or coalesce(new.details->>'templateId','corporate-navy') <> 'corporate-navy'
    or coalesce(new.details->>'themeColor','#0f172a') <> '#0f172a'
    or coalesce(new.details->>'accentColor','#2563eb') <> '#2563eb'
    or coalesce(new.details->>'fontFamily','Outfit') <> 'Outfit') then
   raise exception 'Theme/template customization requires Premium';
 end if;
 if tg_op='UPDATE' and caps->>'themes' <> 'true' and
   (new.details->'themeConfig' is distinct from old.details->'themeConfig'
    or new.details->'themeDraft' is distinct from old.details->'themeDraft'
    or new.details->'templateId' is distinct from old.details->'templateId'
    or new.details->'themeColor' is distinct from old.details->'themeColor'
    or new.details->'accentColor' is distinct from old.details->'accentColor'
    or new.details->'fontFamily' is distinct from old.details->'fontFamily') then
   raise exception 'Theme/template customization requires Premium';
 end if;
 return new;
end $$;
drop trigger if exists apply_package on public.businesses;
create trigger apply_package before insert or update on public.businesses for each row execute function public.apply_business_package();
-- Idempotent reconciliation: uses only the trusted counter, never legacy details.stats.
update public.businesses set is_verified=true where not is_verified and
 exists (select 1 from public.business_package_rules r where r.plan_id=businesses.plan_id
 and r.capabilities->>'verificationViews' is not null
 and businesses.profile_views >= (r.capabilities->>'verificationViews')::bigint);

create table if not exists public.business_profile_view_visitors (
 business_id uuid not null references public.businesses(id) on delete cascade,
 visitor_hash text not null, view_day date not null default (now() at time zone 'UTC')::date,
 primary key(business_id,visitor_hash,view_day)
);
alter table public.business_profile_view_visitors alter column view_day set default (now() at time zone 'UTC')::date;
alter table public.business_profile_view_visitors enable row level security;
revoke all on public.business_profile_view_visitors from public,anon,authenticated;

create or replace function public.record_business_profile_view(p_slug text,p_visitor_hash text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare b public.businesses; added integer; begin
 select * into b from public.businesses where slug=p_slug and is_published=true for update;
 if not found then raise exception 'Business not found'; end if;
 if p_visitor_hash !~ '^[a-f0-9]{64}$' then raise exception 'Invalid visitor hash'; end if;
 insert into public.business_profile_view_visitors(business_id,visitor_hash) values(b.id,p_visitor_hash) on conflict do nothing;
 get diagnostics added=row_count;
 if added > 0 then update public.businesses set profile_views=profile_views+1 where id=b.id returning * into b; end if;
 return jsonb_build_object('totalViews',b.profile_views,'isVerified',b.is_verified);
end $$;

create or replace function public.get_business_package(p_business uuid) returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('planId',b.plan_id,'capabilities',r.capabilities,
  'usage','{"products":0,"services":0,"gallery":0,"events":0,"offers":0}'::jsonb || coalesce((select jsonb_object_agg(resource,used) from public.business_package_usage where business_id=b.id),'{}'::jsonb))
 from public.businesses b join public.business_package_rules r using(plan_id) where b.id=p_business;
$$;
revoke all on function public.get_business_package(uuid),public.record_business_profile_view(text,text),
 public.enforce_business_package_content(),public.apply_business_package() from public,anon,authenticated;
grant execute on function public.get_business_package(uuid),public.record_business_profile_view(text,text) to service_role;
commit;
