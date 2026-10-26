begin;
-- Private upload ledger doubles as a durable cleanup outbox. Never seed it from
-- old public IDs: migration 007 guessed those IDs from URLs.
create table public.cloudinary_assets (
 public_id text primary key,
 secure_url text not null unique,
 owner_id uuid not null,
 state text not null default 'ready' check (state in ('ready','deleting','deleted')),
 cleanup_after timestamptz not null default (now() + interval '24 hours'),
 attempts integer not null default 0,
 last_error text,
 created_at timestamptz not null default now()
);
alter table public.cloudinary_assets enable row level security;
revoke all on public.cloudinary_assets from public, anon, authenticated;
grant all on public.cloudinary_assets to service_role;

-- Conservative substring matching also protects URL-only gallery entries and
-- transformed URLs. False positives retain storage; they never delete live media.
create function public.cloudinary_row_uses(row_data jsonb, asset public.cloudinary_assets)
returns boolean language sql immutable set search_path = public as $$
 select row_data is not null and position(asset.public_id in row_data::text) > 0
$$;

create function public.track_cloudinary_changes() returns trigger
language plpgsql security definer set search_path = public as $$
declare previous jsonb; upcoming jsonb; asset public.cloudinary_assets; pair text[]; url_value text; verified_id text;
begin
 perform pg_advisory_xact_lock(716016);
 if TG_OP <> 'INSERT' then previous := to_jsonb(OLD); end if;
 if TG_OP <> 'DELETE' then upcoming := to_jsonb(NEW); end if;
 if upcoming is not null then
   -- URL-only clients receive the exact ID returned by the upload API. Clear
   -- stale paired IDs when a URL changes; never infer identity from a URL path.
   foreach pair slice 1 in array array[
     ['logo_url','logo_public_id'], ['profile_image_url','profile_image_public_id'],
     ['image_url','image_public_id'], ['cover_image','cover_image_public_id'],
     ['poster_url','poster_public_id']
   ] loop
     if upcoming ? pair[1] and upcoming ? pair[2] then
       url_value := upcoming->>pair[1];
       select public_id into verified_id from public.cloudinary_assets where secure_url = url_value;
       if verified_id is not null or url_value is distinct from previous->>pair[1] then
         upcoming := jsonb_set(upcoming, array[pair[2]], coalesce(to_jsonb(verified_id), 'null'::jsonb));
       end if;
     end if;
   end loop;
   if TG_TABLE_NAME = 'businesses' then
     upcoming := jsonb_set(upcoming, '{details}', coalesce(upcoming->'details','{}') ||
       jsonb_build_object('logoPublicId',upcoming->'logo_public_id','profileImagePublicId',upcoming->'profile_image_public_id'));
   end if;
   NEW := jsonb_populate_record(NEW, upcoming);
 end if;
 if upcoming->>'deleted_at' is not null then upcoming := null; end if;
 for asset in select * from public.cloudinary_assets
 where public.cloudinary_row_uses(previous, cloudinary_assets)
    or public.cloudinary_row_uses(upcoming, cloudinary_assets)
 order by public_id for update loop
   if public.cloudinary_row_uses(upcoming, asset) then
     if asset.state <> 'ready' then
       raise exception 'Image is being deleted or has been deleted; upload it again';
     end if;
   elsif public.cloudinary_row_uses(previous, asset) and asset.state = 'ready' then
     update public.cloudinary_assets set cleanup_after = now() where public_id = asset.public_id;
   end if;
 end loop;
 if TG_OP = 'DELETE' then return OLD; end if;
 return NEW;
end $$;

do $$ declare tab text; begin
 foreach tab in array array['businesses','business_people','products','services','events','offers','gallery_photos','business_categories'] loop
 execute format('create trigger cloudinary_lifecycle before insert or update or delete on public.%I for each row execute function public.track_cloudinary_changes()', tab);
 end loop;
end $$;

create function public.claim_cloudinary_cleanup() returns setof public.cloudinary_assets
language plpgsql security definer set search_path = public as $$
declare asset public.cloudinary_assets; tab text; used boolean; found_ref boolean;
begin
 -- Same lock as writers. Once claimed, triggers prohibit new references, including
 -- while a timed-out Cloudinary request is being reconciled by an idempotent retry.
 perform pg_advisory_xact_lock(716016);
 for asset in select * from public.cloudinary_assets
 where state <> 'deleted' and cleanup_after <= now()
 order by cleanup_after limit 10 for update loop
   found_ref := false;
   foreach tab in array array['businesses','business_people','products','services','events','offers','gallery_photos','business_categories'] loop
     execute format('select exists(select 1 from public.%I r where to_jsonb(r)->>''deleted_at'' is null and public.cloudinary_row_uses(to_jsonb(r), $1))', tab)
       into used using asset;
     if used then found_ref := true; exit; end if;
   end loop;
   if found_ref then
     update public.cloudinary_assets set cleanup_after = now() + interval '24 hours' where public_id = asset.public_id;
   else
     update public.cloudinary_assets set state = 'deleting', attempts = attempts + 1,
       cleanup_after = now() + interval '5 minutes' where public_id = asset.public_id
       returning * into asset;
     return next asset;
   end if;
 end loop;
end $$;
revoke all on function public.cloudinary_row_uses(jsonb, public.cloudinary_assets) from public, anon, authenticated;
revoke all on function public.track_cloudinary_changes() from public, anon, authenticated;
revoke all on function public.claim_cloudinary_cleanup() from public, anon, authenticated;
grant execute on function public.claim_cloudinary_cleanup() to service_role;
commit;
