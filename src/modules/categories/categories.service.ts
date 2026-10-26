import { supabaseAdmin } from '../../config/supabaseClient';
import { resolveCatalog, publicCategoryProjection } from './catalog';
import { ApiError } from '../../utils/apiError';
export type CategoryType = 'product' | 'service';
export async function requireCategoryOwner(businessId: string, req: any) {
 const { data, error } = await supabaseAdmin.from('businesses').select('owner_id').eq('id', businessId).single();
 if (error || !data) throw new ApiError('Business not found',404);
 if (data.owner_id !== req.user.id && !req.isAdmin) throw new ApiError('You do not own this business',403);
}
export function categoryError(error: any): never {
 if (error.code === '23503') throw new ApiError('Category is referenced by existing records or child categories and cannot be deleted, or the selected parent no longer exists.',409);
 if (error.code === '40001' || error.code === '40P01') throw new ApiError('Category changed. Reload and try again.',409);
 if(error.code === 'P0001' && /^(Products|Services) requires Standard or Premium$/.test(error.message || '')) throw new ApiError('Referenced products or services require Standard or Premium before this category can republish them',403);
 if(error.code === 'P0001' && ['Invalid move','Invalid items'].includes(error.message)) throw new ApiError('Invalid move or items do not belong to this business',400);
 if (error.code === 'P0002') throw new ApiError('Category not found',404);
 if (error.code === '23514') throw new ApiError('Invalid category: check its type, allowed leaf selection, active ancestors, references, and hierarchy. Referenced category types cannot change.',400);
 throw new ApiError('Unable to complete category operation',503);
}
export function withAvailability(rows: any[]) {
 const byId = new Map(rows.map(row => [row.id,row]));
 const available = (row: any) => {
  const seen = new Set<string>();
  while (row) {
   if (seen.has(row.id) || row.status !== 'enabled' || !row.is_published) return false;
   seen.add(row.id);
   if (!row.parent_id) return true;
   row = byId.get(row.parent_id);
  }
  return false;
 };
 return rows.map(row => {
  const {business_id,type,legacy_category_id,...category}=row;
  return {...category, visibility: row.is_published, image: row.image_url, parent_category: row.parent_id, available: available(row)};
 });
}
export async function loadGlobalCategories() {
 // Supabase's default response limit is 1000. Fetch every page so deep/imported trees remain complete.
 const rows: any[] = [];
 for (let offset=0;;offset+=1000) {
  const {data,error}=await supabaseAdmin.from('business_categories').select('*').order('created_at').order('id').range(offset,offset+999);
  if(error) categoryError(error);
  rows.push(...(data || []));
  if((data || []).length<1000) break;
 }
 return withAvailability(rows);
}
export async function validateCategory(businessId: string, type: CategoryType | 'business' | 'gallery', id?: string | null, previous?: string | null) {
 if (type === 'product' || type === 'service') {
  const selected = id === undefined ? previous : id;
  const {data: business,error: findError} = await supabaseAdmin.from('businesses').select('global_category_id').eq('id',businessId).single();
  if (findError || !business) throw new ApiError('Business not found',404);
  const {data,error} = await supabaseAdmin.rpc('catalog_category_allowed', {p_business_category:business.global_category_id,p_type:type,p_category:selected ?? null});
  if(error) categoryError(error);
  if(!data) throw new ApiError('Select an active allowed leaf category. Your business category or catalog mapping may need to be configured by Super Admin.',400);
  return;
 }
 if (type === 'business') {
  // Existing profiles can still be maintained during backfill. New/changed assignments must be typed.
  if (businessId && id === undefined) return;
  if (!(await loadGlobalCategories()).some(c => c.id === id && c.catalog_kind === 'business' && c.available))
   throw new ApiError('Select an active business category',400);
  return;
 }
 if (!id || id === previous) return;
 const {data,error}=await supabaseAdmin.rpc('global_category_available',{p_id:id});
 if(error) categoryError(error);
 if(!data) throw new ApiError('Category does not exist or is unavailable for new selections',400);
}
export async function loadMappings(businessCategoryId: string) {
 const rows: any[]=[];
 for(let offset=0;;offset+=1000) {
  const {data,error}=await supabaseAdmin.from('business_catalog_mappings').select('catalog_category_id').eq('business_category_id',businessCategoryId).order('catalog_category_id').range(offset,offset+999);
  if(error) categoryError(error);
  rows.push(...(data || [])); if((data || []).length<1000) break;
 }
 return rows.map(row=>row.catalog_category_id as string);
}
export async function loadCategories(businessId?: string) {
 if(!businessId) return [];
 const {data:business,error}=await supabaseAdmin.from('businesses').select('global_category_id').eq('id',businessId).single();
 if(error) categoryError(error);
 const rows=await loadGlobalCategories();
 const businessCategory=rows.find(c=>c.id===business?.global_category_id && c.catalog_kind==='business');
 if(!businessCategory) return [];
 const roots=await loadMappings(businessCategory.id);
 return (['product','service'] as const).flatMap(type=>resolveCatalog(rows,roots,type,!!businessCategory.available));
}
export async function publicItems(businessId: string, _type: CategoryType, items: any[]) {
 const {data,error}=await supabaseAdmin.from('businesses').select('is_published').eq('id',businessId).single();
 if(error) throw new ApiError('Unable to load business',503);
 if(!data?.is_published) return [];
 const categories=await loadGlobalCategories();
 const visible = new Set(categories.filter(c=>c.available).map(c=>c.id));
 return items.filter(item=>item.is_published!==false && (!item.folder_category_id || visible.has(item.folder_category_id)));
}
/** Resolve names from relations on every read; old free text is only a historical fallback. */
export async function hydrateCategoryNames<T extends Record<string, any>>(rows: T[]): Promise<T[]> {
 if(!rows.some(row=>row.folder_category_id || row.global_category_id)) return rows;
 const categories=await loadGlobalCategories();
 const byId=new Map(categories.map(c=>[c.id,c]));
 return rows.map(row=>{
  const category=byId.get(row.folder_category_id || row.global_category_id);
  if(!category) return row;
  return {...row,category:category.name,category_en:category.name,category_mr:category.name_mr || category.name,
   ...(row.global_category_id ? {details:{...row.details,category:{en:category.name,mr:category.name_mr || category.name}}} : {})};
 });
}

/** Only metadata for already-public items and their ancestors is returned. */
export async function loadPublicCategories(products: any[], services: any[]) {
 return publicCategoryProjection(await loadGlobalCategories(),products,services);
}
