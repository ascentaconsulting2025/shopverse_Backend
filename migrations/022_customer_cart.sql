-- Account-owned cart for WhatsApp enquiries. Run before deploying the cart API.
begin;
create table if not exists public.customer_cart_items (
  customer_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null check (quantity between 1 and 999),
  updated_at timestamptz not null default now(),
  primary key (customer_id, product_id)
);
alter table public.customer_cart_items enable row level security;
revoke all on public.customer_cart_items from anon, authenticated;
grant all on public.customer_cart_items to service_role;
create or replace function public.cart_add_item(p_customer uuid, p_product uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into customer_cart_items(customer_id,product_id,quantity) values(p_customer,p_product,1)
  on conflict(customer_id,product_id) do update set quantity=least(customer_cart_items.quantity+1,999),updated_at=now();
end $$;
revoke all on function public.cart_add_item(uuid,uuid) from public, anon, authenticated;
grant execute on function public.cart_add_item(uuid,uuid) to service_role;
commit;
