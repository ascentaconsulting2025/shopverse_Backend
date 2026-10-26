-- ONLY a fresh disposable database. Never run this against the application database.
\set ON_ERROR_STOP on
\ir packages-fixture.sql
\ir ../migrations/018_global_category_architecture.sql
insert into auth.users values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
insert into profiles(id) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
insert into businesses(id,owner_id,business_name,slug,plan_id) values('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Legacy shop','legacy-shop','premium');
select write_global_category(null,null,'{"name":"Legacy","name_mr":"जुने"}',false);
\ir ../migrations/019_business_catalog_mapping.sql
\ir ../migrations/019_business_catalog_mapping.sql

do $$ declare jewellery uuid; hotel uuid; gold uuid; earrings uuid; rings uuid; silver uuid; repair uuid; shop uuid; other_shop uuid; item uuid;result jsonb;v bigint;begin
 if not exists(select 1 from business_categories where name='Legacy' and name_mr='जुने' and catalog_kind='legacy') then raise exception 'Legacy meaning changed';end if;
 if not exists(select 1 from businesses where slug='legacy-shop' and global_category_id is null) then raise exception 'Guessed legacy assignment';end if;
 jewellery:=(write_global_category(null,null,'{"name":"Jewellery","catalog_kind":"business"}',false)->>'id')::uuid;
 hotel:=(write_global_category(null,null,'{"name":"Hotel","catalog_kind":"business"}',false)->>'id')::uuid;
 gold:=(write_global_category(null,null,'{"name":"Gold","catalog_kind":"product"}',false)->>'id')::uuid;
 earrings:=(write_global_category(null,null,jsonb_build_object('name','Earrings','catalog_kind','product','parent_id',gold),false)->>'id')::uuid;
 rings:=(write_global_category(null,null,jsonb_build_object('name','Rings','catalog_kind','product','parent_id',gold),false)->>'id')::uuid;
 silver:=(write_global_category(null,null,'{"name":"Silver","catalog_kind":"product"}',false)->>'id')::uuid;
 repair:=(write_global_category(null,null,'{"name":"Repair","catalog_kind":"service"}',false)->>'id')::uuid;
 begin perform write_global_category(null,null,jsonb_build_object('name','Wrong child','catalog_kind','service','parent_id',gold),false);raise exception 'Cross type parent accepted';exception when check_violation then null;end;
 begin perform write_global_category(null,null,jsonb_build_object('name','Nested business','catalog_kind','business','parent_id',jewellery),false);raise exception 'Nested business accepted';exception when check_violation then null;end;
 begin perform write_global_category(gold,1,jsonb_build_object('parent_id',earrings),false);raise exception 'Cycle accepted';exception when check_violation then null;end;
 perform replace_business_catalog_mappings(jewellery,'product',array[gold],1);
 perform replace_business_catalog_mappings(jewellery,'service',array[repair],2);
 if not catalog_category_allowed(jewellery,'product',earrings) or not catalog_category_allowed(jewellery,'product',rings) then raise exception 'Parent inheritance failed';end if;
 if catalog_category_allowed(jewellery,'product',gold) then raise exception 'Group selectable';end if;
 if catalog_category_allowed(jewellery,'product',silver) or catalog_category_allowed(jewellery,'product',repair) then raise exception 'Unmapped or wrong type allowed';end if;
 if not catalog_category_allowed(jewellery,'service',repair) then raise exception 'Service mapping failed';end if;
 begin perform replace_business_catalog_mappings(jewellery,'product',array[gold,gold],3);raise exception 'Duplicate map accepted';exception when check_violation then null;end;
 begin perform replace_business_catalog_mappings(jewellery,'product',array[repair],3);raise exception 'Wrong type map accepted';exception when check_violation then null;end;
 begin perform replace_business_catalog_mappings(jewellery,'product',array[silver],1);raise exception 'Stale version accepted';exception when serialization_failure then null;end;
 insert into businesses(owner_id,business_name,slug,plan_id,global_category_id) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Jeweller','jeweller','premium',jewellery) returning id into shop;
 begin insert into businesses(owner_id,business_name,slug,plan_id,global_category_id) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Bad','bad','premium',gold);raise exception 'Product category assigned to business';exception when check_violation then null;end;
 insert into products(business_id,name,name_en,price,folder_category_id,category_id) values(shop,'Studs','Studs',100,earrings,earrings) returning id into item;
 insert into services(business_id,name,name_en,name_mr,folder_category_id,category_id) values(shop,'Repair','Repair','दुरुस्ती',repair,repair);
 begin insert into products(business_id,name,name_en,folder_category_id,category_id) values(shop,'Bad','Bad',silver,silver);raise exception 'Direct unmapped insert accepted';exception when check_violation then null;end;
 begin insert into products(business_id,name,name_en,folder_category_id,category_id) values(shop,'Bad','Bad',repair,repair);raise exception 'Direct wrong type accepted';exception when check_violation then null;end;
 begin update products set category_id=silver where id=item;raise exception 'Alternate column bypass accepted';exception when check_violation then null;end;
 result:=catalog_assignment_impact(jewellery,null,'product',array[]::uuid[]);
 if (result->>'affectedListings')::int<>1 then raise exception 'Mapping preview incorrect';end if;
 perform replace_business_catalog_mappings(jewellery,'product',array[earrings],3);
 if catalog_category_allowed(jewellery,'product',rings) then raise exception 'Child mapping grants sibling';end if;
 perform replace_business_catalog_mappings(jewellery,'product',array[]::uuid[],4);
 if not exists(select 1 from products where id=item and folder_category_id=earrings) then raise exception 'Unmapping deleted listing';end if;
 begin update products set price=200 where id=item;raise exception 'Invalid assignment saved';exception when check_violation then null;end;
 perform replace_business_catalog_mappings(jewellery,'product',array[gold],5);
 update products set price=200 where id=item;
 perform write_global_category(gold,1,'{"status":"disabled"}',false);
 if catalog_category_allowed(jewellery,'product',earrings) then raise exception 'Inactive ancestor allowed';end if;
 begin update products set price=300 where id=item;raise exception 'Disabled assignment saved';exception when check_violation then null;end;
 perform write_global_category(gold,2,'{"status":"enabled"}',false);
 -- A new child inherits a parent mapping and turns its former leaf into a group.
 perform write_global_category(null,null,jsonb_build_object('name','Studs','catalog_kind','product','parent_id',earrings),false);
 if catalog_category_allowed(jewellery,'product',earrings) then raise exception 'Former leaf remained selectable';end if;
 update products set folder_category_id=rings,category_id=rings where id=item;
 result:=catalog_assignment_impact(hotel,shop);
 if (result->>'affectedListings')::int<>2 then raise exception 'Business change preview incorrect';end if;
 update businesses set global_category_id=hotel where id=shop;
 if not exists(select 1 from products where id=item) then raise exception 'Business category change deleted listing';end if;
 begin update products set price=400 where id=item;raise exception 'Changed business permits old category';exception when check_violation then null;end;
 -- Sharing a category never duplicates its record.
 perform replace_business_catalog_mappings(hotel,'product',array[gold],1);
 update products set price=400 where id=item;
 if (select count(*) from business_categories where id=gold)<>1 then raise exception 'Mapping duplicated category';end if;
 begin perform write_global_category(gold,3,'{"catalog_kind":"service"}',false);raise exception 'Mapped type changed';exception when check_violation then null;end;
 -- Contextual creation and mapping are one transaction.
 result:=write_global_category(null,null,jsonb_build_object('name','Cleaning','catalog_kind','service','map_business_category_id',hotel),false);
 if not exists(select 1 from business_catalog_mappings where business_category_id=hotel and catalog_category_id=(result->>'id')::uuid) then raise exception 'Contextual create failed to map';end if;
 begin perform write_global_category(null,null,jsonb_build_object('name','Invalid contextual','catalog_kind','service','map_business_category_id',gold),false);raise exception 'Mapped to non-business';exception when check_violation then null;end;
 if exists(select 1 from business_categories where name='Invalid contextual') then raise exception 'Contextual failure partially committed';end if;
 -- Typed imports are idempotent, previews do not write, and types do not merge.
 result:=import_catalog_categories('[["Imported","Leaf"]]',true,'product');
 if (result->>'created')::int<>2 or exists(select 1 from business_categories where name='Imported') then raise exception 'Preview wrote data';end if;
 perform import_catalog_categories('[["Imported","Leaf"]]',false,'product');
 result:=import_catalog_categories('[["Imported","Leaf"]]',false,'product');
 if (result->>'created')::int<>0 or (result->>'reused')::int<>2 then raise exception 'Import not idempotent';end if;
 perform import_catalog_categories('[["Imported","Leaf"]]',false,'service');
 if (select count(*) from business_categories where name='Imported')<>2 then raise exception 'Import merged types';end if;
 begin perform write_global_category(gold,3,'{}',true);raise exception 'Referenced delete allowed';exception when foreign_key_violation then null;end;
end $$;
set role authenticated;
do $$begin
 begin insert into business_catalog_mappings values(gen_random_uuid(),gen_random_uuid(),now());raise exception 'Owner wrote mapping';exception when insufficient_privilege then null;end;
 begin perform replace_business_catalog_mappings(gen_random_uuid(),'product',array[]::uuid[],1);raise exception 'Owner called mapping RPC';exception when insufficient_privilege then null;end;
end $$;
reset role;
\ir ../migrations/019_business_catalog_mapping.sql
select 'Business catalog database checks passed' as result;
