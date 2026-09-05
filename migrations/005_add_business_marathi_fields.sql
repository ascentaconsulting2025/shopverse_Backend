-- Add nullable Marathi values without changing existing English data.
alter table public.businesses add column if not exists business_name_mr text;
alter table public.businesses add column if not exists category_mr text;
alter table public.businesses add column if not exists owner_name_mr text;
alter table public.businesses add column if not exists designation_mr text;
alter table public.businesses add column if not exists tagline_mr text;
alter table public.businesses add column if not exists description_mr text;