-- Roll back migration 005. This removes only the Marathi columns.
alter table public.businesses drop column if exists business_name_mr;
alter table public.businesses drop column if exists category_mr;
alter table public.businesses drop column if exists owner_name_mr;
alter table public.businesses drop column if exists designation_mr;
alter table public.businesses drop column if exists tagline_mr;
alter table public.businesses drop column if exists description_mr;