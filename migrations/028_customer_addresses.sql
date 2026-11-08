begin;
create table public.customer_addresses (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 full_name text not null check(length(trim(full_name)) between 1 and 120), phone_number text not null check(length(trim(phone_number)) between 7 and 25),
 address_line_1 text not null check(length(trim(address_line_1)) between 1 and 150), address_line_2 text not null check(length(trim(address_line_2)) between 1 and 150), landmark text,
 city text not null check(length(trim(city)) between 1 and 100), state text not null check(length(trim(state)) between 1 and 100), postal_code text not null check(length(trim(postal_code)) between 1 and 20), country text not null check(length(trim(country)) between 1 and 100),
 address_type text not null check(address_type in ('Home','Office','Other')), custom_label text, latitude numeric check(latitude between -90 and 90), longitude numeric check(longitude between -180 and 180),
 is_default boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(address_type <> 'Other' or length(trim(coalesce(custom_label,''))) > 0), check((latitude is null) = (longitude is null)),
 check(lower(trim(country)) not in ('india','in') or postal_code ~ '^[1-9][0-9]{5}$')
);
create index customer_addresses_user_idx on public.customer_addresses(user_id);
create unique index customer_addresses_default_idx on public.customer_addresses(user_id) where is_default;
alter table public.customer_addresses enable row level security;
create policy address_read on public.customer_addresses for select to authenticated using (user_id=auth.uid());
-- Writes go through the authenticated backend and serialized functions below.
revoke all on public.customer_addresses from public, anon, authenticated;
grant select on public.customer_addresses to authenticated;
grant all on public.customer_addresses to service_role;
alter table public.marketplace_orders add column delivery_address_snapshot jsonb;
create function public.save_customer_address(p_user uuid,p_id uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare result customer_addresses%rowtype; make_default boolean;
begin
 perform pg_advisory_xact_lock(hashtextextended('address:' || p_user::text,0));
 if p_id is not null and not exists(select 1 from customer_addresses where id=p_id and user_id=p_user) then raise exception 'Address not found'; end if;
 make_default := coalesce((p_data->>'is_default')::boolean,false) or not exists(select 1 from customer_addresses where user_id=p_user);
 if make_default then update customer_addresses set is_default=false where user_id=p_user and is_default and id is distinct from p_id; end if;
 if p_id is null then
 insert into customer_addresses(user_id,full_name,phone_number,address_line_1,address_line_2,landmark,city,state,postal_code,country,address_type,custom_label,latitude,longitude,is_default)
 values(p_user,p_data->>'full_name',p_data->>'phone_number',p_data->>'address_line_1',p_data->>'address_line_2',nullif(p_data->>'landmark',''),p_data->>'city',p_data->>'state',p_data->>'postal_code',p_data->>'country',p_data->>'address_type',nullif(p_data->>'custom_label',''),(p_data->>'latitude')::numeric,(p_data->>'longitude')::numeric,make_default) returning * into result;
 else
 update customer_addresses set full_name=p_data->>'full_name',phone_number=p_data->>'phone_number',address_line_1=p_data->>'address_line_1',address_line_2=p_data->>'address_line_2',landmark=nullif(p_data->>'landmark',''),city=p_data->>'city',state=p_data->>'state',postal_code=p_data->>'postal_code',country=p_data->>'country',address_type=p_data->>'address_type',custom_label=nullif(p_data->>'custom_label',''),latitude=(p_data->>'latitude')::numeric,longitude=(p_data->>'longitude')::numeric,is_default=make_default,updated_at=now() where id=p_id and user_id=p_user returning * into result;
 end if;
 if not exists(select 1 from customer_addresses where user_id=p_user and is_default) then update customer_addresses set is_default=true where id=result.id returning * into result; end if;
 return to_jsonb(result);
end $$;
create function public.delete_customer_address(p_user uuid,p_id uuid) returns boolean language plpgsql security definer set search_path=public as $$
declare was_default boolean;
begin
 perform pg_advisory_xact_lock(hashtextextended('address:' || p_user::text,0));
 delete from customer_addresses where user_id=p_user and id=p_id returning is_default into was_default;
 if not found then return false; end if;
 if was_default then update customer_addresses set is_default=true where id=(select id from customer_addresses where user_id=p_user order by created_at,id limit 1); end if;
 return true;
end $$;
create function public.place_saved_address_request(p_customer uuid,p_store uuid,p_key uuid,p_address_id uuid,p_expected jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare a customer_addresses%rowtype; result jsonb; address_text text; prior uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_customer::text || ':' || p_key::text,0));
 select id into prior from marketplace_orders where customer_id=p_customer and request_key=p_key;
 if prior is not null then
   select id into prior from marketplace_store_orders where order_id=prior and business_id=p_store;
   if prior is null then raise exception 'Request key already used'; end if;
   return jsonb_build_object('store_order_id',prior,'replayed',true);
 end if;
 select * into a from customer_addresses where user_id=p_customer and id=p_address_id for share;
 if not found then raise exception 'Address unavailable'; end if;
 address_text := concat_ws(', ',a.address_line_1,a.address_line_2,nullif(a.landmark,''),a.city,a.state,a.postal_code,a.country);
 result := place_whatsapp_store_request(p_customer,p_store,p_key,a.full_name,case when regexp_replace(a.phone_number,'[^0-9]','','g') ~ '^[6-9][0-9]{9}$' then '91' || regexp_replace(a.phone_number,'[^0-9]','','g') else regexp_replace(a.phone_number,'[^0-9]','','g') end,address_text,p_expected);
 update marketplace_orders set delivery_address_snapshot=to_jsonb(a)-'user_id'-'created_at'-'updated_at'-'is_default' where id=(select order_id from marketplace_store_orders where id=(result->>'store_order_id')::uuid);
 return result;
end $$;
revoke all on function public.save_customer_address(uuid,uuid,jsonb), public.delete_customer_address(uuid,uuid), public.place_saved_address_request(uuid,uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.save_customer_address(uuid,uuid,jsonb), public.delete_customer_address(uuid,uuid), public.place_saved_address_request(uuid,uuid,uuid,uuid,jsonb) to service_role;
commit;
