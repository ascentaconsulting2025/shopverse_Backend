-- Private identity documents; all access is mediated by the backend.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('delivery-partner-documents','delivery-partner-documents',false,5242880,array['image/jpeg','image/png'])
on conflict(id) do nothing;
-- Refuse to operate if an existing bucket is public or has different security settings.
do $$ begin
 if not exists(select 1 from storage.buckets where id='delivery-partner-documents' and public=false and file_size_limit=5242880 and allowed_mime_types = array['image/jpeg','image/png']) then
  raise exception 'Delivery document bucket configuration differs';
 end if;
end $$;
create function public.register_delivery_identity_document(p_user uuid,p_path text) returns jsonb language plpgsql security definer set search_path=public as $$
declare profile public.delivery_partner_profiles%rowtype; doc public.delivery_partner_documents%rowtype;
begin
 select * into profile from public.delivery_partner_profiles where user_id=p_user for update;
 if not found or profile.partner_type <> 'independent' or profile.verification_status not in ('draft','additional_information_required') then raise exception 'Application is not editable'; end if;
 if p_path is null or p_path not like profile.id::text || '/%' then raise exception 'Invalid document path'; end if;
 insert into public.delivery_partner_documents(partner_id,document_type,storage_path) values(profile.id,'identity',p_path) returning * into doc;
 return jsonb_build_object('id',doc.id,'created_at',doc.created_at);
end $$;
revoke all on function public.register_delivery_identity_document(uuid,text) from public,anon,authenticated;
grant execute on function public.register_delivery_identity_document(uuid,text) to service_role;
commit;
