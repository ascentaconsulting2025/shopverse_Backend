-- Keep public digital-card URLs unique for all existing installations.
create unique index if not exists idx_businesses_slug on public.businesses(slug);