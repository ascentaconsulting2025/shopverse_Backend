-- Disposable database test, after loading a minimal fixture schema and migration 010.
-- All fixture data is rolled back.
begin;
insert into businesses(id,owner_id,is_published) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true),
 ('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
insert into business_categories(id,business_id,type,name) values
 ('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111','product','Electronics'),
 ('44444444-4444-4444-8444-444444444444','11111111-1111-4111-8111-111111111111','service','Consulting'),
 ('55555555-5555-4555-8555-555555555555','22222222-2222-4222-8222-222222222222','product','Other business');
insert into products(id,business_id,name) values
 ('66666666-6666-4666-8666-666666666666','11111111-1111-4111-8111-111111111111','Existing product'),
 ('77777777-7777-4777-8777-777777777777','22222222-2222-4222-8222-222222222222','Foreign product');
insert into services(id,business_id,name) values
 ('88888888-8888-4888-8888-888888888888','11111111-1111-4111-8111-111111111111','Existing service');
do $$ begin
 begin update products set folder_category_id='44444444-4444-4444-8444-444444444444' where name='Existing product'; raise exception 'Cross-type assignment accepted'; exception when foreign_key_violation then null; end;
 begin update products set folder_category_id='55555555-5555-4555-8555-555555555555' where name='Existing product'; raise exception 'Cross-business assignment accepted'; exception when foreign_key_violation then null; end;
 begin update services set folder_category_id='33333333-3333-4333-8333-333333333333'; raise exception 'Service accepted product category'; exception when foreign_key_violation then null; end;
end $$;
select move_category_items('11111111-1111-4111-8111-111111111111','product',array['66666666-6666-4666-8666-666666666666']::uuid[],'33333333-3333-4333-8333-333333333333');
do $$ begin
 if not exists(select 1 from products where name='Existing product' and folder_category_id='33333333-3333-4333-8333-333333333333') then raise exception 'Move failed'; end if;
 begin
  perform move_category_items('11111111-1111-4111-8111-111111111111','product',array['66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777']::uuid[],null);
  raise exception 'Mixed-owner bulk move accepted';
 exception when raise_exception then if sqlerrm <> 'Invalid items' then raise; end if; end;
 if not exists(select 1 from products where name='Existing product' and folder_category_id='33333333-3333-4333-8333-333333333333') then raise exception 'Failed bulk move changed data'; end if;
end $$;
select reorder_categories('11111111-1111-4111-8111-111111111111','product',array['33333333-3333-4333-8333-333333333333']::uuid[]);
do $$ begin
 begin perform reorder_categories('11111111-1111-4111-8111-111111111111','product',array['55555555-5555-4555-8555-555555555555']::uuid[]); raise exception 'Foreign reorder accepted';
 exception when raise_exception then if sqlerrm <> 'Category list changed; refresh and try again' then raise; end if; end;
end $$;
delete from business_categories where id='33333333-3333-4333-8333-333333333333';
do $$ begin
 if (select count(*) from products) <> 2 then raise exception 'Category deletion removed items'; end if;
 if not exists(select 1 from products where name='Existing product' and folder_category_id is null) then raise exception 'Category deletion did not unassign item'; end if;
end $$;
update business_categories set is_published=false where type='service';
update services set folder_category_id='44444444-4444-4444-8444-444444444444';
update products set is_published=false where name='Foreign product';
set local role anon;
do $$ begin
 if (select count(*) from products) <> 1 then raise exception 'Draft product leaked through RLS'; end if;
 if exists(select 1 from services) then raise exception 'Hidden service category leaked through RLS'; end if;
 if exists(select 1 from business_categories where type='service') then raise exception 'Hidden category leaked through RLS'; end if;
end $$;
reset role;
rollback;
