-- Order records for seller confirmation. This migration does not create checkout.
begin;
create table if not exists public.marketplace_orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references auth.users(id) on delete set null,
  order_number text not null unique,
  customer_name text not null,
  customer_phone text not null,
  delivery_address text not null,
  created_at timestamptz not null default now()
);
create table if not exists public.marketplace_store_orders (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.marketplace_orders(id) on delete restrict,
  business_id uuid references public.businesses(id) on delete set null,
  business_name text not null,
  store_order_number text not null unique,
  status text not null default 'PENDING' check (status in ('PENDING','ACCEPTED','PROCESSING','READY_FOR_DISPATCH','OUT_FOR_DELIVERY','DELIVERED','REJECTED','CANCELLED')),
  subtotal numeric(12,2),
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(order_id,business_id)
);
create table if not exists public.marketplace_order_items (
  id uuid primary key default gen_random_uuid(),
  store_order_id uuid not null references public.marketplace_store_orders(id) on delete restrict,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2)
);
create table if not exists public.marketplace_order_status_history (
  id uuid primary key default gen_random_uuid(),
  store_order_id uuid not null references public.marketplace_store_orders(id) on delete restrict,
  previous_status text not null,
  new_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists marketplace_store_orders_business_created_idx on public.marketplace_store_orders(business_id,created_at desc);
create index if not exists marketplace_store_orders_confirmed_idx on public.marketplace_store_orders(confirmed_at desc) where confirmed_at is not null;
create index if not exists marketplace_order_items_store_idx on public.marketplace_order_items(store_order_id);
alter table public.marketplace_orders enable row level security;
alter table public.marketplace_store_orders enable row level security;
alter table public.marketplace_order_items enable row level security;
alter table public.marketplace_order_status_history enable row level security;
revoke all on public.marketplace_orders,public.marketplace_store_orders,public.marketplace_order_items,public.marketplace_order_status_history from public,anon,authenticated;
grant all on public.marketplace_orders,public.marketplace_store_orders,public.marketplace_order_items,public.marketplace_order_status_history to service_role;
create or replace function public.confirm_marketplace_store_order(p_order uuid,p_actor uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor) then return false; end if;
 if target.status <> 'PENDING' then return false; end if;
 update marketplace_store_orders set status='ACCEPTED',confirmed_at=now() where id=target.id;
 insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(target.id,'PENDING','ACCEPTED',p_actor);
 return true;
end $$;
revoke all on function public.confirm_marketplace_store_order(uuid,uuid) from public,anon,authenticated;
grant execute on function public.confirm_marketplace_store_order(uuid,uuid) to service_role;
commit;
