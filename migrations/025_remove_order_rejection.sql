-- Clean up installations that already ran the earlier rejection implementation.
-- Preserve recorded reasons if they exist; dropping them would erase order history.
begin;
drop function if exists public.reject_marketplace_store_order(uuid,uuid,text);
do $$
declare has_reasons boolean;
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='marketplace_store_orders' and column_name='rejection_reason') then
    execute 'select exists(select 1 from public.marketplace_store_orders where rejection_reason is not null)' into has_reasons;
    if has_reasons then
      raise notice 'Keeping rejection_reason to preserve recorded order history';
    else
      alter table public.marketplace_store_orders drop column rejection_reason;
    end if;
  end if;
end $$;
commit;
