-- Fresh disposable database ONLY; includes the category-mapping integration fixture.
\set ON_ERROR_STOP on
\ir business-catalog-database.sql
\ir ../migrations/020_marketplace_category_hierarchy.sql
\ir ../migrations/020_marketplace_category_hierarchy.sql

do $$ declare business_type uuid;root uuid;parent uuid;leaf uuid;sibling uuid;other_leaf uuid;shop uuid;service_root uuid;service_parent uuid;service_leaf uuid;item uuid;facets jsonb;path jsonb;begin
 business_type:=(write_global_category(null,null,'{"name":"Food","catalog_kind":"business"}',false)->>'id')::uuid;
 root:=(write_global_category(null,null,'{"name":"Food","catalog_kind":"product"}',false)->>'id')::uuid;
 parent:=(write_global_category(null,null,jsonb_build_object('name','Maharashtrian','name_mr','महाराष्ट्रीयन','catalog_kind','product','parent_id',root),false)->>'id')::uuid;
 leaf:=(write_global_category(null,null,jsonb_build_object('name','Starters','catalog_kind','product','parent_id',parent),false)->>'id')::uuid;
 sibling:=(write_global_category(null,null,jsonb_build_object('name','Gujarati','catalog_kind','product','parent_id',root),false)->>'id')::uuid;
 other_leaf:=(write_global_category(null,null,jsonb_build_object('name','Starters','catalog_kind','product','parent_id',sibling),false)->>'id')::uuid;
 service_root:=(write_global_category(null,null,'{"name":"Food Services","catalog_kind":"service"}',false)->>'id')::uuid;
 service_parent:=(write_global_category(null,null,jsonb_build_object('name','Catering','catalog_kind','service','parent_id',service_root),false)->>'id')::uuid;
 service_leaf:=(write_global_category(null,null,jsonb_build_object('name','Event Catering','catalog_kind','service','parent_id',service_parent),false)->>'id')::uuid;
 perform replace_business_catalog_mappings(business_type,'product',array[root],1);
 perform replace_business_catalog_mappings(business_type,'service',array[service_root],2);
 insert into businesses(owner_id,business_name,slug,plan_id,global_category_id,is_published) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Food shop','food-hierarchy-test','premium',business_type,true) returning id into shop;
 insert into products(business_id,name,name_en,folder_category_id,category_id) values(shop,'Maharashtrian Starter','Maharashtrian Starter',leaf,leaf) returning id into item;
 insert into products(business_id,name,name_en,folder_category_id,category_id) values(shop,'Gujarati Starter','Gujarati Starter',other_leaf,other_leaf);
 insert into products(business_id,name,name_en,folder_category_id,category_id,is_published) values(shop,'Hidden Starter','Hidden Starter',leaf,leaf,false);
 insert into services(business_id,name,name_en,name_mr,folder_category_id,category_id) values(shop,'Catering Package','Catering Package','',service_leaf,service_leaf);
 select category_path into path from explore_products where id=item;
 if path->0->>'name'<>'Food' or path->1->>'name'<>'Maharashtrian' or path->2->>'name'<>'Starters' then raise exception 'Intermediate parent missing: %',path;end if;
 if path->1->>'name_mr'<>'महाराष्ट्रीयन' then raise exception 'Translation lost';end if;
 if (select count(*) from explore_products where business_id=shop and category_path @> jsonb_build_array(jsonb_build_object('id',parent)))<>1 then raise exception 'Parent filter leaks sibling or hidden items';end if;
 if (select count(*) from explore_products where business_id=shop and category_path @> jsonb_build_array(jsonb_build_object('id',root)))<>2 then raise exception 'Root filter missed descendants';end if;
 facets:=explore_facets();
 if (select count(*) from jsonb_array_elements(facets) f where f->>'category'='Food' and f->>'subcategory'='Starters')<>2 then raise exception 'Same-named leaves merged across parents';end if;
 if exists(select 1 from jsonb_array_elements(facets) f where f->>'category'='Food' and (f->>'count')::int<>1) then raise exception 'Hidden item included in counts';end if;
 if not exists(select 1 from explore_services where business_id=shop and category_path->1->>'name'='Catering' and category_path @> jsonb_build_array(jsonb_build_object('id',service_parent))) then raise exception 'Service ancestry missing';end if;
 if not exists(select 1 from jsonb_array_elements(explore_service_facets()) f where f->>'category'='Food' and f->'category_path'->1->>'name'='Catering') then raise exception 'Service facets omit parents';end if;
 perform write_global_category(parent,1,'{"status":"disabled"}',false);
 if exists(select 1 from explore_products where id=item) then raise exception 'Disabled ancestry exposed listing';end if;
end $$;
set role authenticated;
do $$ begin
 begin perform explore_category_path(gen_random_uuid());raise exception 'Private taxonomy helper exposed';exception when insufficient_privilege then null;end;
 begin perform * from explore_products;raise exception 'Private catalog view exposed';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'Marketplace hierarchy database checks passed' as result;
