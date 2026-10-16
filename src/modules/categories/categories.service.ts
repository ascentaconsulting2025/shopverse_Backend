import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
export type CategoryType = 'product' | 'service';
export async function requireCategoryOwner(businessId: string, req: any) {
 const { data } = await supabaseAdmin.from('businesses').select('owner_id').eq('id', businessId).single();
 if (!data) throw new ApiError('Business not found',404);
 if (data.owner_id !== req.user.id && !req.isAdmin) throw new ApiError('You do not own this business',403);
}
export async function validateCategory(businessId: string, type: CategoryType, id?: string | null) {
 if (!id) return;
 const { data, error } = await supabaseAdmin.from('business_categories').select('id').eq('id',id).eq('business_id',businessId).eq('type',type).maybeSingle();
 if (error || !data) throw new ApiError('Category does not belong to this business and item type',400);
}
export async function loadCategories(businessId: string) {
 const { data,error } = await supabaseAdmin.from('business_categories').select('*').eq('business_id',businessId).order('display_order').order('created_at').order('id');
 if(error) throw new ApiError(error.message,400);
 return data || [];
}
export async function publicItems(businessId: string, type: CategoryType, items: any[]) {
 const { data } = await supabaseAdmin.from('businesses').select('is_published').eq('id',businessId).single();
 if (!data?.is_published) return [];
 const categories = await loadCategories(businessId);
 return items.filter(item => item.is_published !== false && (!item.folder_category_id || categories.some(c => c.id === item.folder_category_id && c.type === type && c.is_published)));
}
