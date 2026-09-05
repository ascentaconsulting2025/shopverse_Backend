import { asyncHandler } from '../../utils/asyncHandler';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { supabaseAdmin } from '../../config/supabaseClient';
import { toBusinessWrite, toCard } from './business.mapper';
import { slugify, uniqueSuffix } from '../../utils/generateSlug';
import { sectionVisibilitySchema } from './business.schema';

const toVisibility = (row: any) => ({
  products: row?.products ?? true,
  services: row?.services ?? true,
  special_offers: row?.special_offers ?? true,
  photo_gallery: row?.photo_gallery ?? true,
  upcoming_events: row?.upcoming_events ?? true,
});

async function loadVisibility(businessId: string) {
  const { data, error } = await supabaseAdmin
    .from('business_section_visibility')
    .select('products, services, special_offers, photo_gallery, upcoming_events')
    .eq('business_id', businessId)
    .maybeSingle();
  if (error) throw new ApiError(error.message, 400);
  return toVisibility(data);
}

async function requireOwnedBusiness(businessId: string, req: any) {
  const { data, error } = await supabaseAdmin.from('businesses').select('id, owner_id').eq('id', businessId).single();
  if (error || !data) throw new ApiError('Business not found', 404);
  if (data.owner_id !== req.user.id && !req.isAdmin) throw new ApiError('You do not own this business', 403);
}

const missingPhoneColumn = (error: any) =>
  (error?.code === 'PGRST204' || error?.code === '42703') && /phone/i.test(error.message || '');

const toService = (row: any) => ({
  id: row.id,
  name: { en: row.name_en ?? row.name ?? '', mr: row.name_mr ?? row.name ?? '' },
  description: { en: row.details_en ?? row.details ?? '', mr: row.details_mr ?? row.details ?? '' },
  startingPrice: Number(row.starting_price || 0),
  duration: { en: row.duration_en ?? '', mr: row.duration_mr ?? '' },
  category: { en: row.category_en ?? '', mr: row.category_mr ?? '' },
  image: row.cover_image || '',
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const toProduct = (row: any) => ({
  id: row.id,
  name: { en: row.name_en ?? row.name ?? '', mr: row.name_mr ?? row.name ?? '' },
  description: { en: row.description_en ?? row.description ?? '', mr: row.description_mr ?? row.description ?? '' },
  price: Number(row.price || 0),
  originalPrice: row.original_price == null ? undefined : Number(row.original_price),
  image: row.image_url || '',
  category: { en: row.category_en ?? row.category ?? '', mr: row.category_mr ?? row.category ?? '' },
  isAvailable: row.is_available ?? true,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const toEvent = (row: any) => ({ id: row.id, title: { en: row.event_name_en, mr: row.event_name_mr }, eventName: { en: row.event_name_en, mr: row.event_name_mr }, description: { en: row.description_en, mr: row.description_mr }, date: row.event_date, time: row.start_time, venue: { en: row.venue_en, mr: row.venue_mr }, enquiryNo: row.enquiry_number, eventLink: row.website_url || '', photo: row.poster_url || '', image: row.poster_url || '', isActive: row.is_active });
const toOffer = (row: any) => ({ id: row.id, title: { en: row.offer_title_en, mr: row.offer_title_mr }, description: { en: row.terms_en, mr: row.terms_mr }, discountBadge: { en: row.discount_badge_en, mr: row.discount_badge_mr }, discountPercentage: row.discount_percentage == null ? undefined : Number(row.discount_percentage), couponCode: row.coupon_code, validUntil: { en: row.validity_en, mr: row.validity_mr }, isActive: row.is_active });
const toGallery = (row: any) => ({ id: row.id, url: row.image_url, imageUrl: row.image_url, caption: row.caption, category: row.category, sortOrder: row.sort_order, isActive: row.is_active });

async function loadProducts(businessId: string) {
  const { data, error } = await supabaseAdmin.from('products').select('*').eq('business_id', businessId).order('sort_order').order('created_at', { ascending: false });
  if (error) throw new ApiError(error.message, 400);
  return data || [];
}

async function loadServices(businessId: string) {
  const { data, error } = await supabaseAdmin.from('services').select('*').eq('business_id', businessId).order('created_at', { ascending: false });
  if (error) return null;
  return data || [];
}

async function loadContent(businessId: string) {
  const [events, offers, gallery] = await Promise.all([
    supabaseAdmin.from('events').select('*').eq('business_id', businessId).eq('is_active', true).is('deleted_at', null).order('created_at', { ascending: false }),
    supabaseAdmin.from('offers').select('*').eq('business_id', businessId).eq('is_active', true).is('deleted_at', null).order('created_at', { ascending: false }),
    supabaseAdmin.from('gallery_photos').select('*').eq('business_id', businessId).eq('is_active', true).is('deleted_at', null).order('sort_order').order('created_at', { ascending: false }),
  ]);
  return { events: events.data || [], offers: offers.data || [], gallery: gallery.data || [] };
}

async function insertBusiness(card: Record<string, any>, ownerId: string) {
  let result = await supabaseAdmin.from('businesses').insert(toBusinessWrite(card, ownerId)).select().single();
  if (missingPhoneColumn(result.error)) {
    result = await supabaseAdmin.from('businesses').insert(toBusinessWrite(card, ownerId, false)).select().single();
  }
  return result;
}

async function saveBusiness(id: string, card: Record<string, any>) {
  let result = await supabaseAdmin.from('businesses').update(toBusinessWrite(card)).eq('id', id).select().single();
  if (missingPhoneColumn(result.error)) {
    result = await supabaseAdmin.from('businesses').update(toBusinessWrite(card, undefined, false)).eq('id', id).select().single();
  }
  return result;
}

export const createBusiness = asyncHandler(async (req, res) => {
  const user = (req as any).user;
  const name = typeof req.body.businessName === 'object'
    ? req.body.businessName.en || req.body.businessName.mr
    : req.body.businessName;
  const baseSlug = slugify(req.body.slug || name || 'business') || `business-${uniqueSuffix()}`;
  let lastError: any = null;

  for (let attempt = 0; attempt < 8; attempt += 1) {
    const slug = attempt === 0 ? baseSlug : `${baseSlug}-${uniqueSuffix()}`;
    const result = await insertBusiness({ ...req.body, slug }, user.id);
    if (!result.error) {
      res.status(201).json(apiSuccess(toCard(result.data)));
      return;
    }
    lastError = result.error;
    if (result.error.code !== '23505') break;
  }

  throw new ApiError(lastError?.message || 'Unable to create business', lastError?.code === '23505' ? 409 : 400);
});

export const getBusinessBySlug = asyncHandler(async (req, res) => {
  const { data, error } = await supabaseAdmin.from('businesses').select('*').eq('slug', req.params.slug).eq('is_published', true).single();
  if (error || !data) throw new ApiError('Business not found', 404);
  const [products, services, content, visibility] = await Promise.all([loadProducts(data.id), loadServices(data.id), loadContent(data.id), loadVisibility(data.id)]);
  const card = toCard(data);
  res.json(apiSuccess({
    ...card,
    sectionVisibility: { products: visibility.products, services: visibility.services, offers: visibility.special_offers, gallery: visibility.photo_gallery, events: visibility.upcoming_events },
    products: products.map(toProduct),
    ...(services ? { services: services.map(toService) } : {}),
    events: content.events.map(toEvent), offers: content.offers.map(toOffer), gallery: content.gallery.map(toGallery),
  }));
});

export const updateBusiness = asyncHandler(async (req, res) => {
  const user = (req as any).user;
  const { data: current, error: findError } = await supabaseAdmin.from('businesses').select('*').eq('id', req.params.id).single();
  if (findError || !current) throw new ApiError('Business not found', 404);
  if (current.owner_id !== user.id && !(req as any).isAdmin) throw new ApiError('You do not own this business', 403);
  const merged = { ...toCard(current), ...req.body, id: current.id, slug: current.slug };
  const { data, error } = await saveBusiness(current.id, merged);
  if (error) throw new ApiError(error.message, 400);
  res.json(apiSuccess(toCard(data)));
});

export const deleteBusiness = asyncHandler(async (req, res) => {
  const user = (req as any).user;
  const { data: current, error: findError } = await supabaseAdmin
    .from('businesses')
    .select('id, owner_id')
    .eq('id', req.params.id)
    .single();
  if (findError || !current) throw new ApiError('Business not found', 404);
  if (current.owner_id !== user.id && !(req as any).isAdmin) throw new ApiError('You do not own this business', 403);

  const { error } = await supabaseAdmin.from('businesses').delete().eq('id', current.id);
  if (error) throw new ApiError(error.message, 400);
  res.json(apiSuccess(null));
});

export const listMyBusinesses = asyncHandler(async (req, res) => {
  let query = supabaseAdmin.from('businesses').select('*').order('created_at', { ascending: false });
  if (!(req as any).isAdmin) query = query.eq('owner_id', (req as any).user.id);
  const { data, error } = await query;
  if (error) throw new ApiError(error.message, 400);
  const cards = await Promise.all(data.map(async (row) => {
    const [products, services, visibility] = await Promise.all([loadProducts(row.id), loadServices(row.id), loadVisibility(row.id)]);
    const card = toCard(row);
    return {
      ...card,
      sectionVisibility: { products: visibility.products, services: visibility.services, offers: visibility.special_offers, gallery: visibility.photo_gallery, events: visibility.upcoming_events },
      products: products.map(toProduct),
      ...(services ? { services: services.map(toService) } : {}),
    };
  }));
  res.json(apiSuccess(cards));
});

export const getSectionVisibility = asyncHandler(async (req, res) => {
  await requireOwnedBusiness(req.params.id, req);
  res.json(apiSuccess(await loadVisibility(req.params.id)));
});

export const updateSectionVisibility = asyncHandler(async (req, res) => {
  await requireOwnedBusiness(req.params.id, req);
  const visibility = sectionVisibilitySchema.parse(req.body);
  const { data, error } = await supabaseAdmin
    .from('business_section_visibility')
    .upsert({ business_id: req.params.id, ...visibility, updated_at: new Date().toISOString() }, { onConflict: 'business_id' })
    .select('products, services, special_offers, photo_gallery, upcoming_events')
    .single();
  if (error) throw new ApiError(error.message, 400);
  res.json(apiSuccess(toVisibility(data)));
});

export const getBusinessUsage = asyncHandler(async (req, res) => {
  await requireOwnedBusiness(req.params.id, req);
  const [products, services, offers, gallery, events] = await Promise.all([
    supabaseAdmin.from('products').select('id', { count: 'exact', head: true }).eq('business_id', req.params.id),
    supabaseAdmin.from('services').select('id', { count: 'exact', head: true }).eq('business_id', req.params.id),
    supabaseAdmin.from('offers').select('id', { count: 'exact', head: true }).eq('business_id', req.params.id).eq('is_active', true).is('deleted_at', null),
    supabaseAdmin.from('gallery_photos').select('id', { count: 'exact', head: true }).eq('business_id', req.params.id).eq('is_active', true).is('deleted_at', null),
    supabaseAdmin.from('events').select('id', { count: 'exact', head: true }).eq('business_id', req.params.id).eq('is_active', true).is('deleted_at', null),
  ]);
  const failed = [products, services, offers, gallery, events].find((item) => item.error);
  if (failed?.error) throw new ApiError(failed.error.message, 400);
  res.json(apiSuccess({ products: products.count || 0, services: services.count || 0, offers: offers.count || 0, gallery: gallery.count || 0, events: events.count || 0 }));
});
