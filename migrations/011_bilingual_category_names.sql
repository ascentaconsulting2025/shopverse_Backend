-- Run after 010_category_folders.sql. Existing category names remain unchanged.
begin;
alter table public.business_categories
 add column if not exists name_mr text not null default '';
commit;
