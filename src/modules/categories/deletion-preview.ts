import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { categoryError, loadCategoryArchitecture, loadMappings } from './categories.service';

const previewLimit = 50;

/** The database still decides whether deletion is safe; this preview explains known dependencies. */
export async function categoryDeletionPreview(id: string, offset = 0) {
 const categories = await loadCategoryArchitecture();
 const category = categories.find(c => c.id === id);
 if (!category) throw new ApiError('Category not found', 404);
 const children = categories.filter(c => c.parent_id === id).map(c => ({id:c.id, name:c.name, name_mr:c.name_mr, catalog_kind:c.catalog_kind}));
 const owners = (category.business_category_ids as string[]).map(ownerId => {
  const owner = categories.find(c => c.id === ownerId);
  return {id:ownerId, name:owner?.name || ownerId, direct:(category.direct_business_category_ids as string[]).includes(ownerId)};
 });
 const specs = [
  {key:'businesses', table:'businesses', select:'id,business_name', column:'global_category_id'},
  {key:'products', table:'products', select:'id,name,name_en,business_id', column:'folder_category_id'},
  {key:'services', table:'services', select:'id,name,name_en,business_id', column:'folder_category_id'},
  {key:'gallery', table:'gallery_photos', select:'id,caption,business_id', column:'global_category_id'},
 ] as const;
 const groups = await Promise.all(specs.map(async spec => {
  let query = supabaseAdmin.from(spec.table).select(spec.select, {count:'exact'});
  query = spec.key === 'products' || spec.key === 'services'
   ? query.or(`folder_category_id.eq.${id},category_id.eq.${id}`)
   : query.eq(spec.column,id);
  const {data,error,count} = await query.order('id').range(offset,offset+previewLimit-1);
  if(error) categoryError(error);
  if(count === null) throw new ApiError('Unable to count category dependencies',503);
  return {key:spec.key, count, rows:(data || []) as any[]};
 }));
 const businessIds = [...new Set(groups.flatMap(group => group.rows.map(row => row.business_id).filter(Boolean)))];
 const businessNames = new Map<string,string>();
 if(businessIds.length){
  const {data,error} = await supabaseAdmin.from('businesses').select('id,business_name').in('id',businessIds);
  if(error) categoryError(error);
  for(const business of data || []) businessNames.set(business.id,business.business_name);
 }
 const references = Object.fromEntries(groups.map(group => [group.key, {
  count:group.count,
  items:group.rows.map(row => ({id:row.id, name:row.business_name || row.name_en || row.name || row.caption || 'Untitled', businessId:row.business_id || null, businessName:businessNames.get(row.business_id) || null})),
 }]));
 const mappedIds = category.catalog_kind === 'business' ? await loadMappings(id) : [];
 const mappings = mappedIds.map(mappedId => ({id:mappedId,name:categories.find(c=>c.id===mappedId)?.name || mappedId}));
 return {children, owners, mappings, references, previewLimit, offset, blocked:children.length > 0 || owners.length > 1 || groups.some(group=>group.count>0)};
}
