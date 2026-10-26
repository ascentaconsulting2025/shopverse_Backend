-- Fresh disposable database only: target schema without historical listing_categories.
\set ON_ERROR_STOP on
\ir packages-fixture.sql
\ir ../migrations/018_global_category_architecture.sql
\ir ../migrations/018_global_category_architecture.sql
do $$ declare root uuid; child uuid; begin
 if exists(select 1 from business_categories) then raise exception 'Migration seeded sample categories';end if;
 root:=(write_global_category(null,null,'{"name":"Fresh root"}',false)->>'id')::uuid;
 child:=(write_global_category(null,null,jsonb_build_object('name','Fresh child','parent_id',root),false)->>'id')::uuid;
 if not global_category_available(child) then raise exception 'Fresh category unavailable';end if;
 begin perform write_global_category(child,1,jsonb_build_object('parent_id',gen_random_uuid()),false);raise exception 'Missing parent accepted';exception when foreign_key_violation then null;end;
 if (select parent_id from business_categories where id=child)<>root then raise exception 'Failed parent edit partially saved';end if;
end $$;
