import { asyncHandler } from '../../utils/asyncHandler';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { supabaseAdmin } from '../../config/supabaseClient';
import { toBusinessWrite, toBusinessPerson, toCard } from './business.mapper';
import { slugify, uniqueSuffix } from '../../utils/generateSlug';
import { sectionVisibilitySchema } from './business.schema';
import { deleteCloudinaryImage } from '../../utils/cloudinaryAsset';

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
  startingPrice: row.starting_price == null || Number(row.starting_price) <= 0 ? undefined : Number(row.starting_price),
  duration: { en: row.duration_en ?? '', mr: row.duration_mr ?? '' },
  category: { en: row.category_en ?? '', mr: row.category_mr ?? '' },
  image: row.cover_image || '', imagePublicId: row.cover_image_public_id || '',
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const toProduct = (row: any) => ({
  id: row.id,
  name: { en: row.name_en ?? row.name ?? '', mr: row.name_mr ?? row.name ?? '' },
  description: { en: row.description_en ?? row.description ?? '', mr: row.description_mr ?? row.description ?? '' },
  price: row.price == null || Number(row.price) <= 0 ? undefined : Number(row.price),
  originalPrice: row.original_price == null || Number(row.original_price) <= 0 ? undefined : Number(row.original_price),
  image: row.image_url || '', imagePublicId: row.image_public_id || '',
  category: { en: row.category_en ?? row.category ?? '', mr: row.category_mr ?? row.category ?? '' },
  isAvailable: row.is_available ?? true,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const toEvent = (row: any) => ({ id: row.id, title: { en: row.event_name_en, mr: row.event_name_mr }, eventName: { en: row.event_name_en, mr: row.event_name_mr }, description: { en: row.description_en, mr: row.description_mr }, date: row.event_date, time: row.start_time, venue: { en: row.venue_en, mr: row.venue_mr }, enquiryNo: row.enquiry_number, eventLink: row.website_url || '', photo: row.poster_url || '', image: row.poster_url || '', imagePublicId: row.poster_public_id || '', isActive: row.is_active });
const toOffer = (row: any) => ({ id: row.id, title: { en: row.offer_title_en, mr: row.offer_title_mr }, description: { en: row.terms_en, mr: row.terms_mr }, discountBadge: { en: row.discount_badge_en, mr: row.discount_badge_mr }, discountPercentage: row.discount_percentage == null ? undefined : Number(row.discount_percentage), couponCode: row.coupon_code, validUntil: { en: row.validity_en, mr: row.validity_mr }, imageUrl: row.image_url || '', imagePublicId: row.image_public_id || '', isActive: row.is_active });
const toGallery = (row: any) => ({ id: row.id, url: row.image_url, imageUrl: row.image_url, imagePublicId: row.image_public_id || '', caption: row.caption, category: row.category, sortOrder: row.sort_order, isActive: row.is_active });

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

async function loadPeople(businessId: string, includeInactive = false) {
  let query = supabaseAdmin.from('business_people').select('*').eq('business_id', businessId).order('display_order').order('created_at');
  if (!includeInactive) query = query.eq('is_active', true);
  const { data, error } = await query;
  if (error) throw new ApiError(error.message, 400);
  return (data || []).map(toBusinessPerson);
}

/** Replaces the visible leadership set without deleting history/assets. */
async function savePeople(businessId: string, people: any[] | undefined) {
  if (people === undefined) return;
  const activePrimary = people.filter((person) => person.isActive !== false && person.isPrimary);
  if (activePrimary.length > 1) throw new ApiError('Only one active primary person is allowed', 400);
  if (people.some((person) => person.isActive !== false) && activePrimary.length !== 1) throw new ApiError('Exactly one active primary person is required', 400);

  const incomingIds = people.map((person) => person.id).filter(Boolean);
  const existing = await supabaseAdmin.from('business_people').select('id').eq('business_id', businessId);
  if (existing.error) throw new ApiError(existing.error.message, 400);
  const existingIds = new Set((existing.data || []).map((person: any) => person.id));
  if (incomingIds.some((id) => !existingIds.has(id))) throw new ApiError('A leadership record does not belong to this business', 400);

  // Deactivate omitted records; this is recoverable and prevents stale people from rendering.
  const omittedIds = [...existingIds].filter((id) => !incomingIds.includes(id));
  if (omittedIds.length) {
    const { error } = await supabaseAdmin.from('business_people').update({ is_active: false, is_primary: false, updated_at: new Date().toISOString() }).in('id', omittedIds);
    if (error) throw new ApiError(error.message, 400);
  }
  // Clear an existing primary first so the partial unique index is never violated.
  const clearPrimary = await supabaseAdmin.from('business_people').update({ is_primary: false }).eq('business_id', businessId).eq('is_primary', true);
  if (clearPrimary.error) throw new ApiError(clearPrimary.error.message, 400);
  for (const person of people) {
    const payload = {
      business_id: businessId,
      full_name_en: person.fullName.en || person.fullName.mr,
      full_name_mr: person.fullName.mr || null,
      designation_en: person.designation?.en || null,
      designation_mr: person.designation?.mr || null,
      description_en: person.description?.en || null,
      description_mr: person.description?.mr || null,
      profile_image_url: person.profileImage || null,
      profile_image_public_id: person.profileImagePublicId || null,
      display_order: person.displayOrder ?? 0,
      is_primary: person.isPrimary === true,
      is_active: person.isActive !== false,
      updated_at: new Date().toISOString(),
    };
    const result = person.id
      ? await supabaseAdmin.from('business_people').update(payload).eq('id', person.id).eq('business_id', businessId)
      : await supabaseAdmin.from('business_people').insert(payload);
    if (result.error) throw new ApiError(result.error.message, 400);
  }
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
      await savePeople(result.data.id, req.body.people);
      res.status(201).json(apiSuccess({ ...toCard(result.data), people: await loadPeople(result.data.id, true) }));
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
  const [products, services, content, visibility, people] = await Promise.all([loadProducts(data.id), loadServices(data.id), loadContent(data.id), loadVisibility(data.id), loadPeople(data.id)]);
  const card = toCard(data);
  delete card.themeDraft;
  res.json(apiSuccess({
    ...card,
    sectionVisibility: { products: visibility.products, services: visibility.services, offers: visibility.special_offers, gallery: visibility.photo_gallery, events: visibility.upcoming_events },
    products: products.map(toProduct),
    ...(services ? { services: services.map(toService) } : {}),
    events: content.events.map(toEvent), offers: content.offers.map(toOffer), gallery: content.gallery.map(toGallery),
    people,
  }));
});

export const getBusinessCount = asyncHandler(async (_req, res) => {
  const { count, error } = await supabaseAdmin
    .from('businesses')
    .select('id', { count: 'exact', head: true })
    .eq('is_published', true);
  if (error) throw new ApiError(error.message, 400);
  res.json(apiSuccess({ count: count || 0 }));
});

/** Public marketplace feed. Only published businesses and active child records are exposed. */
export const listMarketplace = asyncHandler(async (req, res) => {
  const search = String(req.query.search || '').trim().toLowerCase();
  const kind = String(req.query.kind || 'all');
  const { data, error } = await supabaseAdmin
    .from('businesses')
    .select('*')
    .eq('is_published', true)
    .order('updated_at', { ascending: false });
  if (error) throw new ApiError(error.message, 400);

  const businesses = await Promise.all((data || []).map(async (row) => {
    const [products, services, content, people] = await Promise.all([
      loadProducts(row.id),
      loadServices(row.id),
      loadContent(row.id),
      loadPeople(row.id),
    ]);
    const card = toCard(row);
    return {
      id: row.id,
      slug: row.slug,
      businessName: card.businessName,
      ownerName: card.ownerName,
      category: card.category,
      logo: card.logo,
      profileImage: card.profileImage,
      address: card.address,
      isVerified: card.isVerified,
      people,
      products: products.filter((item: any) => item.is_available !== false).map(toProduct),
      services: (services || []).map(toService),
      events: content.events.filter((item: any) => item.is_active !== false).map(toEvent),
    };
  }));

  const result = businesses.flatMap((business: any) => {
    const businessText = [business.businessName?.en, business.businessName?.mr, business.category?.en, business.category?.mr, business.ownerName?.en, business.ownerName?.mr].join(' ').toLowerCase();
    const matches = (item: any) => !search || [item.title?.en, item.title?.mr, item.name?.en, item.name?.mr, item.fullName?.en, item.fullName?.mr, item.designation?.en, item.designation?.mr, item.description?.en, item.description?.mr, item.category?.en, item.category?.mr, item.venue?.en, item.venue?.mr, businessText].join(' ').toLowerCase().includes(search);
    const records: any[] = [];
    if (kind === 'all' || kind === 'business') {
      if (!search || businessText.includes(search)) {
        records.push({
          type: 'business',
          item: {
            id: business.id,
            name: business.businessName,
            category: business.category,
            description: business.category,
          },
          business,
        });
      }
    }
    if (kind === 'all' || kind === 'product') business.products.filter(matches).forEach((item: any) => records.push({ type: 'product', item, business }));
    if (kind === 'all' || kind === 'service') business.services.filter(matches).forEach((item: any) => records.push({ type: 'service', item, business }));
    if (kind === 'all' || kind === 'event') business.events.filter(matches).forEach((item: any) => records.push({ type: 'event', item, business }));
    if (kind === 'all' || kind === 'owner') {
      business.people.filter(matches).forEach((person: any) => records.push({ type: 'owner', item: person, business }));
    }
    return records;
  });

  res.json(apiSuccess(result));
});

export const updateBusiness = asyncHandler(async (req, res) => {
  const user = (req as any).user;
  const { data: current, error: findError } = await supabaseAdmin.from('businesses').select('*').eq('id', req.params.id).single();
  if (findError || !current) throw new ApiError('Business not found', 404);
  if (current.owner_id !== user.id && !(req as any).isAdmin) throw new ApiError('You do not own this business', 403);
  const themeChanged = ['themeConfig', 'themeDraft'].some(key =>
    req.body[key] != null && JSON.stringify(req.body[key]) !== JSON.stringify(current.details?.[key]),
  );
  if (themeChanged && current.plan_id !== 'premium') {
    throw new ApiError('Premium plan is required to save or publish a custom theme', 403);
  }
  const merged = { ...toCard(current), ...req.body, id: current.id, slug: req.body.slug ?? current.slug };
  const nextLogoPublicId = toBusinessWrite(merged).logo_public_id;
  if (current.logo_public_id && current.logo_public_id !== nextLogoPublicId) {
    await deleteCloudinaryImage(current.logo_public_id, current.id);
  }
  const { data, error } = await saveBusiness(current.id, merged);
  if (error) {
    if (error.code === '23505' && /slug/i.test(error.message || '')) {
      throw new ApiError('This slug is already in use. Please choose another slug.', 409);
    }
    throw new ApiError('Unable to update business information', 400);
  }
  await savePeople(current.id, req.body.people);
  res.json(apiSuccess({ ...toCard(data), people: await loadPeople(current.id, true) }));
});

export const deleteBusiness = asyncHandler(async (req, res) => {
  const user = (req as any).user;
  const { data: current, error: findError } = await supabaseAdmin
    .from('businesses')
    .select('id, owner_id, logo_public_id')
    .eq('id', req.params.id)
    .single();
  if (findError || !current) throw new ApiError('Business not found', 404);
  if (current.owner_id !== user.id && !(req as any).isAdmin) throw new ApiError('You do not own this business', 403);

  const [products, services, events, gallery] = await Promise.all([
    supabaseAdmin.from('products').select('id, image_public_id').eq('business_id', current.id),
    supabaseAdmin.from('services').select('id, cover_image_public_id').eq('business_id', current.id),
    supabaseAdmin.from('events').select('id, poster_public_id').eq('business_id', current.id),
    supabaseAdmin.from('gallery_photos').select('id, image_public_id').eq('business_id', current.id),
  ]);
  const childQueryError = [products, services, events, gallery].find((result) => result.error)?.error;
  if (childQueryError) throw new ApiError(childQueryError.message, 400);
  await Promise.all([
    deleteCloudinaryImage(current.logo_public_id, current.id),
    ...(products.data || []).map((row) => deleteCloudinaryImage(row.image_public_id, row.id)),
    ...(services.data || []).map((row) => deleteCloudinaryImage(row.cover_image_public_id, row.id)),
    ...(events.data || []).map((row) => deleteCloudinaryImage(row.poster_public_id, row.id)),
    ...(gallery.data || []).map((row) => deleteCloudinaryImage(row.image_public_id, row.id)),
  ]);

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
    const [products, services, visibility, people] = await Promise.all([loadProducts(row.id), loadServices(row.id), loadVisibility(row.id), loadPeople(row.id, true)]);
    const card = toCard(row);
    return {
      ...card,
      sectionVisibility: { products: visibility.products, services: visibility.services, offers: visibility.special_offers, gallery: visibility.photo_gallery, events: visibility.upcoming_events },
      products: products.map(toProduct),
      ...(services ? { services: services.map(toService) } : {}),
      people,
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
