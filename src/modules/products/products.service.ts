import { validateCategory, hydrateCategoryNames, categoryError } from '../categories/categories.service';
import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { cloudinaryPublicIdFromUrl } from '../../utils/cloudinaryAsset';

export const productSelect = '*';

export const requireProduct = async (id: string) => {
	const { data, error } = await supabaseAdmin.from('products').select(productSelect).eq('id', id).single();
	if (error || !data) throw new ApiError('Product not found', 404);
	return (await hydrateCategoryNames([data]))[0];
};

export const productsService = {
	async list(businessId: string) {
		const { data, error } = await supabaseAdmin.from('products').select(productSelect)
			.eq('business_id', businessId).order('sort_order').order('created_at', { ascending: false });
		if (error) throw new ApiError(error.message, 400);
		return hydrateCategoryNames(data || []);
	},
	async create(businessId: string, input: any) {
    await validateCategory(businessId, 'product', input.categoryId);
		const { data, error } = await supabaseAdmin.from('products').insert({
			business_id: businessId,
      ...(input.images !== undefined ? {images: input.images} : {}),
      ...(input.specifications !== undefined ? {specifications: input.specifications} : {}),
      folder_category_id: input.categoryId ?? null,
      category_id: input.categoryId ?? null,
      is_published: input.isPublished ?? true,
			name: input.name.en || input.name.mr,
			name_en: input.name.en,
			name_mr: input.name.mr,
			description: input.description.en || input.description.mr || null,
			description_en: input.description.en,
			description_mr: input.description.mr,
			price: input.price,
			original_price: input.originalPrice ?? null,
			image_url: input.image || null,
			image_public_id: input.imagePublicId || cloudinaryPublicIdFromUrl(input.image) || null,
			category: input.categoryId ? null : input.category?.en || input.category?.mr || null,
			category_en: input.categoryId ? null : input.category?.en || null,
			category_mr: input.categoryId ? null : input.category?.mr || null,
			is_available: input.isAvailable,
			sort_order: input.sortOrder ?? 0,
		}).select(productSelect).single();
		if (error) { if (['23503','23514','40001','40P01'].includes(error.code)) categoryError(error); throw new ApiError(error.message,400); }
		return (await hydrateCategoryNames([data]))[0];
	},
	async update(id: string, input: any) {
    const current = await requireProduct(id);
    await validateCategory(current.business_id, 'product', input.categoryId, current.folder_category_id);
		const update: Record<string, unknown> = { updated_at: new Date().toISOString() };
		if (input.images !== undefined) update.images = input.images;
    if (input.specifications !== undefined) update.specifications = input.specifications;
    if (input.categoryId !== undefined) { update.folder_category_id = input.categoryId; update.category_id = input.categoryId; }
    if(input.categoryId && input.categoryId !== current.folder_category_id) { update.category=null; update.category_en=null; update.category_mr=null; }
    if (input.isPublished !== undefined) update.is_published = input.isPublished;
    if (input.name !== undefined) { update.name = input.name.en || input.name.mr; update.name_en = input.name.en; update.name_mr = input.name.mr; }
		if (input.description !== undefined) { update.description = input.description.en || input.description.mr || null; update.description_en = input.description.en; update.description_mr = input.description.mr; }
		if (input.price !== undefined) update.price = input.price;
		if (input.originalPrice !== undefined) update.original_price = input.originalPrice;
		if (input.image !== undefined) {
			update.image_url = input.image || null;
			update.image_public_id = input.imagePublicId || cloudinaryPublicIdFromUrl(input.image) || null;
		}
		if (input.category !== undefined && !(input.categoryId ?? current.folder_category_id)) { update.category = input.category?.en || input.category?.mr || null; update.category_en = input.category?.en || null; update.category_mr = input.category?.mr || null; }
		if (input.isAvailable !== undefined) update.is_available = input.isAvailable;
		if (input.sortOrder !== undefined) update.sort_order = input.sortOrder;
		const { data, error } = await supabaseAdmin.from('products').update(update).eq('id', id).select(productSelect).single();
		if (error && ['23503','23514','40001','40P01'].includes(error.code)) categoryError(error);
    if (error || !data) throw new ApiError(error?.message || 'Product not found', error ? 400 : 404);
		return (await hydrateCategoryNames([data]))[0];
	},
	async remove(id: string) {
		const { error } = await supabaseAdmin.from('products').delete().eq('id', id);
		if (error) throw new ApiError(error.message, 400);
	},
};
