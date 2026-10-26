import { hydrateCategoryNames, validateCategory } from '../categories/categories.service';
import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { cloudinaryPublicIdFromUrl } from '../../utils/cloudinaryAsset';

const table = (kind: 'events' | 'offers' | 'gallery') => kind === 'gallery' ? 'gallery_photos' : kind;
export const requireContent = async (kind: 'events' | 'offers' | 'gallery', id: string) => { const { data, error } = await supabaseAdmin.from(table(kind)).select('*').eq('id', id).is('deleted_at', null).single(); if (error || !data) throw new ApiError(`${kind} record not found`, 404); return kind === 'gallery' ? (await hydrateCategoryNames([data]))[0] : data; };
export const contentService = {
  async list(kind: 'events' | 'offers' | 'gallery', businessId: string, query: any) {
    const page = Math.max(Number(query.page) || 1, 1); const limit = Math.min(Math.max(Number(query.limit) || 50, 1), 100);
    let request = supabaseAdmin.from(table(kind)).select('*', { count: 'exact' }).eq('business_id', businessId).is('deleted_at', null);
    if (query.active !== undefined) request = request.eq('is_active', query.active !== 'false');
    if (query.search && kind === 'events') request = request.ilike('event_name_en', `%${query.search}%`);
    if (query.search && kind === 'offers') request = request.ilike('offer_title_en', `%${query.search}%`);
    if (query.search && kind === 'gallery') request = request.ilike('caption', `%${query.search}%`);
    const { data, error, count } = await request.order('created_at', { ascending: false }).range((page - 1) * limit, page * limit - 1); if (error) throw new ApiError(error.message, 400); return { items: kind === 'gallery' ? await hydrateCategoryNames(data || []) : data || [], page, limit, total: count || 0 };
  },
  async create(kind: 'events' | 'offers' | 'gallery', businessId: string, input: any) {
    if (kind === 'gallery') await validateCategory(businessId, 'gallery', input.categoryId);
    const payload = kind === 'events' ? { business_id: businessId, event_name_en: input.title.en, event_name_mr: input.title.mr, description_en: input.description.en, description_mr: input.description.mr, event_date: input.date, start_time: input.time, venue_en: input.venue.en, venue_mr: input.venue.mr, enquiry_number: input.enquiryNo, website_url: input.eventLink || null, poster_url: input.photo || input.image || null, is_active: input.isActive } : kind === 'offers' ? { business_id: businessId, offer_title_en: input.title.en, offer_title_mr: input.title.mr, discount_percentage: input.discountPercentage ?? null, discount_badge_en: input.discountBadge.en, discount_badge_mr: input.discountBadge.mr, coupon_code: String(input.couponCode ?? '').trim(), validity_en: String(input.validUntil?.en ?? '').trim(), validity_mr: String(input.validUntil?.mr ?? '').trim(), terms_en: String(input.terms?.en ?? input.description?.en ?? '').trim(), terms_mr: String(input.terms?.mr ?? input.description?.mr ?? '').trim(), image_url: input.imageUrl || null, image_public_id: input.imagePublicId || cloudinaryPublicIdFromUrl(input.imageUrl) || null, is_active: input.isActive } : { business_id: businessId, image_url: input.url ?? input.imageUrl, caption: typeof input.caption === 'string' ? input.caption : input.caption.en || input.caption.mr, category: typeof input.category === 'string' ? input.category : input.category.en || input.category.mr, sort_order: input.sortOrder, is_active: input.isActive };
    const imageUrl = input.photo ?? input.image ?? input.url ?? input.imageUrl;
    if (kind === 'events') (payload as any).poster_public_id = input.imagePublicId || cloudinaryPublicIdFromUrl(imageUrl) || null;
    if (kind === 'gallery') (payload as any).global_category_id = input.categoryId ?? null;
    if (kind === 'gallery' && input.categoryId) (payload as any).category = '';
    if (kind === 'gallery') (payload as any).image_public_id = input.imagePublicId || cloudinaryPublicIdFromUrl(imageUrl) || null;
    const { data, error } = await supabaseAdmin.from(table(kind)).insert(payload as any).select('*').single(); if (error) throw new ApiError(error.code === '23505' ? 'Coupon code already exists' : error.message, error.code === '23505' ? 409 : 400); return kind === 'gallery' ? (await hydrateCategoryNames([data]))[0] : data;
  },
  async update(kind: 'events' | 'offers' | 'gallery', id: string, input: any) { const current = await requireContent(kind, id); if(kind === 'gallery') await validateCategory(current.business_id, 'gallery', input.categoryId, current.global_category_id); const imageUrl = input.photo ?? input.image ?? input.url ?? input.imageUrl; const map: any = kind === 'events' ? { event_name_en: input.title?.en, event_name_mr: input.title?.mr, description_en: input.description?.en, description_mr: input.description?.mr, event_date: input.date, start_time: input.time, venue_en: input.venue?.en, venue_mr: input.venue?.mr, enquiry_number: input.enquiryNo, website_url: input.eventLink, poster_url: input.photo ?? input.image, is_active: input.isActive } : kind === 'offers' ? { offer_title_en: input.title?.en, offer_title_mr: input.title?.mr, discount_percentage: input.discountPercentage, discount_badge_en: input.discountBadge?.en, discount_badge_mr: input.discountBadge?.mr, coupon_code: String(input.couponCode ?? '').trim(), validity_en: String(input.validUntil?.en ?? '').trim(), validity_mr: String(input.validUntil?.mr ?? '').trim(), terms_en: input.terms?.en || input.description?.en, terms_mr: input.terms?.mr || input.description?.mr, image_url: input.imageUrl, image_public_id: input.imagePublicId || cloudinaryPublicIdFromUrl(input.imageUrl) || null, is_active: input.isActive } : { image_url: input.url ?? input.imageUrl, caption: typeof input.caption === 'string' ? input.caption : input.caption?.en || input.caption?.mr, category: typeof input.category === 'string' ? input.category : input.category?.en || input.category?.mr, sort_order: input.sortOrder, is_active: input.isActive }; if (kind === 'gallery' && input.categoryId !== undefined) map.global_category_id = input.categoryId; if (kind === 'gallery' && input.categoryId) map.category = ''; if (kind === 'offers' && input.imageUrl === undefined) delete map.image_public_id; Object.keys(map).forEach(key => map[key] === undefined && delete map[key]); if (imageUrl !== undefined && kind === 'events') map.poster_public_id = input.imagePublicId || cloudinaryPublicIdFromUrl(imageUrl) || null; if (imageUrl !== undefined && kind === 'gallery') map.image_public_id = input.imagePublicId || cloudinaryPublicIdFromUrl(imageUrl) || null; const { data, error } = await supabaseAdmin.from(table(kind)).update({ ...map, updated_at: new Date().toISOString() }).eq('id', id).select('*').single(); if (error || !data) throw new ApiError(error?.message || 'Record not found', error ? 400 : 404); return kind === 'gallery' ? (await hydrateCategoryNames([data]))[0] : data; },
  async remove(kind: 'events' | 'offers' | 'gallery', id: string) {
    await requireContent(kind, id);
    if (kind === 'gallery' || kind === 'events' || kind === 'offers') {
      const { data, error } = await supabaseAdmin
        .from(table(kind))
        .update({ deleted_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq('id', id)
        .select('id')
        .maybeSingle();
      if (error) throw new ApiError(error.message, 400);
      if (!data) throw new ApiError(`${kind} record not found`, 404);
      return;
    }
  }
};
