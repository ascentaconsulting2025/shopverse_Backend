-- Only the trusted backend may call this function. It derives p_is_admin from
-- the verified session, never from customer-supplied request data.
begin;
create or replace function public.manage_store_order(p_order uuid, p_actor uuid, p_is_admin boolean, p_action text)
returns boolean language plpgsql security definer set search_path = public as $$
declare target public.marketplace_store_orders%rowtype; next_status text;
begin
  if p_actor is null or p_action not in ('accept', 'reject') then return false; end if;
  select * into target from public.marketplace_store_orders where id = p_order for update;
  if not found or (p_is_admin is not true and not exists
    (select 1 from public.businesses where id = target.business_id and owner_id = p_actor)) then
    return false;
  end if;
  if target.status <> 'PENDING' then return false; end if;
  next_status := case when p_action = 'accept' then 'ACCEPTED' else 'REJECTED' end;
  update public.marketplace_store_orders
    set status = next_status, confirmed_at = case when p_action = 'accept' then now() else null end
    where id = target.id;
  insert into public.marketplace_order_status_history(store_order_id, previous_status, new_status, changed_by)
    values(target.id, 'PENDING', next_status, p_actor);
  return true;
end $$;
revoke all on function public.manage_store_order(uuid,uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.manage_store_order(uuid,uuid,boolean,text) to service_role;
commit;
