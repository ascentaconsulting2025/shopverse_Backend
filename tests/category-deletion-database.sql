-- Fresh disposable database only.
\set ON_ERROR_STOP on
\ir business-catalog-database.sql
\ir ../migrations/021_delete_unused_category_branches.sql
\ir ../migrations/021_delete_unused_category_branches.sql

do $$ declare business_category uuid; root uuid; leaf uuid; shop uuid; item uuid; v bigint; begin
 business_category:=(write_global_category(null,null,'{"name":"Deletion business","catalog_kind":"business"}',false)->>'id')::uuid;
 root:=(write_global_category(null,null,'{"name":"Food deletion fixture","catalog_kind":"product"}',false)->>'id')::uuid;
 leaf:=(write_global_category(null,null,jsonb_build_object('name','Starters','catalog_kind','product','parent_id',root),false)->>'id')::uuid;
 perform replace_business_catalog_mappings(business_category,'product',array[root,leaf],1);
 -- A mapped leaf with no records can be deleted; mapping versions must advance.
 perform write_global_category(leaf,1,'{}',true);
 if exists(select 1 from business_categories where id=leaf) or exists(select 1 from business_catalog_mappings where catalog_category_id=leaf) then raise exception 'Unused mapped leaf was not deleted';end if;
 if (select version from business_categories where id=business_category)<>3 then raise exception 'Mapping version not advanced';end if;
 leaf:=(write_global_category(null,null,jsonb_build_object('name','Starters','catalog_kind','product','parent_id',root),false)->>'id')::uuid;
 insert into businesses(owner_id,business_name,slug,plan_id,global_category_id)
 values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Deletion test','deletion-test','premium',business_category) returning id into shop;
 insert into products(business_id,name,name_en,folder_category_id,category_id) values(shop,'Protected','Protected',leaf,leaf) returning id into item;
 select version into v from business_categories where id=business_category;
 begin perform write_global_category(root,1,'{}',true);raise exception 'Referenced descendant deleted';exception when foreign_key_violation then null;end;
 if not exists(select 1 from products where id=item) or not exists(select 1 from business_categories where id=root) or not exists(select 1 from business_categories where id=leaf) then raise exception 'Deletion partially committed';end if;
 if not exists(select 1 from business_catalog_mappings where business_category_id=business_category and catalog_category_id=root) or (select version from business_categories where id=business_category)<>v then raise exception 'Failed delete changed mappings';end if;
 begin perform write_global_category(business_category,v,'{}',true);raise exception 'Assigned business category deleted';exception when foreign_key_violation then null;end;
 delete from products where id=item;
 begin perform write_global_category(root,999,'{}',true);raise exception 'Stale deletion allowed';exception when serialization_failure then null;end;
 perform write_global_category(root,1,'{}',true);
 if exists(select 1 from business_categories where id in(root,leaf)) or exists(select 1 from business_catalog_mappings where catalog_category_id in(root,leaf)) then raise exception 'Unused branch remains';end if;
 if not exists(select 1 from businesses where id=shop) then raise exception 'Unrelated business deleted';end if;
end $$;
select 'Category deletion checks passed' as result;
