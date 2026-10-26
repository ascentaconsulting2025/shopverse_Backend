import { supabaseAdmin } from '../../config/supabaseClient';
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
 if (error.code === '23514') throw new ApiError('Invalid or unavailable category, or a parent would create a hierarchy cycle.',400);
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
export async function validateCategory(_businessId: string, _type: CategoryType | 'business' | 'gallery', id?: string | null, previous?: string | null) {
 if (!id || id === previous) return;
 const {data,error}=await supabaseAdmin.rpc('global_category_available',{p_id:id});
 if(error) categoryError(error);
 if(!data) throw new ApiError('Category does not exist or is unavailable for new selections',400);
}
/** Compatibility projection for existing card consumers; both item types share the same IDs. */
export async function loadCategories(_businessId?: string) {
 const rows = await loadGlobalCategories();
 return rows.flatMap(row => (['product','service'] as const).map(type=>({...row,type})));
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
