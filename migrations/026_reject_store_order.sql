-- Allow the owning seller to reject a pending store order, with an audit entry.
-- This does not send a customer notification or collect a reason.
begin;
create or replace function public.reject_store_order(p_order uuid, p_actor uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare target public.marketplace_store_orders%rowtype;
begin
  select * into target from public.marketplace_store_orders where id = p_order for update;
  if not found or not exists (select 1 from public.businesses where id = target.business_id and owner_id = p_actor) then
    return false;
  end if;
  if target.status <> 'PENDING' then return false; end if;
  update public.marketplace_store_orders set status = 'REJECTED' where id = target.id;
  insert into public.marketplace_order_status_history(store_order_id, previous_status, new_status, changed_by)
  values(target.id, 'PENDING', 'REJECTED', p_actor);
  return true;
end $$;
revoke all on function public.reject_store_order(uuid,uuid) from public, anon, authenticated;
grant execute on function public.reject_store_order(uuid,uuid) to service_role;
commit;
