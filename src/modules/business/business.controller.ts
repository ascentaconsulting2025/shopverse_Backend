import { createHmac } from 'node:crypto';
import { env } from '../../config/env';
import { getBusinessPackage, protectBusinessFields, requirePackageFeature } from '../packages/packages.service';
import { loadCategories, loadGlobalCategories, loadPublicCategories, publicItems, hydrateCategoryNames, validateCategory } from '../categories/categories.service';
import { asyncHandler } from '../../utils/asyncHandler';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { createAuthClient, supabaseAdmin } from '../../config/supabaseClient';
import { toBusinessWrite, toBusinessPerson, toCard } from './business.mapper';
import { slugify, uniqueSuffix } from '../../utils/generateSlug';
import { deleteBusinessSchema, sectionVisibilitySchema } from './business.schema';
import { cloudinaryPublicIdFromUrl } from '../../utils/cloudinaryAsset';

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
  id: row.id, categoryId: row.folder_category_id ?? null, isPublished: row.is_published !== false,
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
  images: row.images || [], specifications: row.specifications || {},
  id: row.id, categoryId: row.folder_category_id ?? null, isPublished: row.is_published !== false,
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
const toGallery = (row: any) => ({ id: row.id, url: row.image_url, imageUrl: row.image_url, imagePublicId: row.image_public_id || '', caption: row.caption, category: row.category, categoryId: row.global_category_id ?? null, sortOrder: row.sort_order, isActive: row.is_active });

async function loadProducts(businessId: string) {
  const { data, error } = await supabaseAdmin.from('products').select('*').eq('business_id', businessId).order('sort_order').order('created_at', { ascending: false });
  if (error) throw new ApiError(error.message, 400);
  return hydrateCategoryNames(data || []);
}

async function loadServices(businessId: string) {
  const { data, error } = await supabaseAdmin.from('services').select('*').eq('business_id', businessId).order('created_at', { ascending: false });
  if (error) return null;
  return hydrateCategoryNames(data || []);
}

async function loadContent(businessId: string, includeInactive = false) {
  const query = (table: string) => {
    let result = supabaseAdmin.from(table).select('*').eq('business_id', businessId).is('deleted_at', null);
    if (!includeInactive) result = result.eq('is_active', true);
    return result;
  };
  const [events, offers, gallery] = await Promise.all([
    query('events').order('created_at', { ascending: false }),
    query('offers').order('created_at', { ascending: false }),
    query('gallery_photos').order('sort_order').order('created_at', { ascending: false }),
  ]);
  const failed = [events, offers, gallery].find(result => result.error);
  if (failed?.error) throw new ApiError(failed.error.message, 400);
  return { events: events.data || [], offers: offers.data || [], gallery: await hydrateCategoryNames(gallery.data || []) };
}

async function loadPeople(businessId: string, includeInactive = false) {
  let query = supabaseAdmin.from('business_people').select('*').eq('business_id', businessId).order('display_order').order('created_at');
  if (!includeInactive) query = query.eq('is_active', true);
  const { data, error } = await query;
  if (error) throw new ApiError(error.message, 400);
  return (data || []).map(toBusinessPerson);
}

/** Replaces the visible leadership set; omitted photos are released for cleanup. */
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
    const { error } = await supabaseAdmin.from('business_people').update({ is_active: false, is_primary: false, profile_image_url: null, profile_image_public_id: null, updated_at: new Date().toISOString() }).in('id', omittedIds);
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
      profile_image_public_id: person.profileImagePublicId || cloudinaryPublicIdFromUrl(person.profileImage) || null,
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

async function saveBusiness(id: string, card: Record<string, any>, trusted: { plan: boolean; verification: boolean }) {
  const payload = (phone = true) => {
    const value: any = toBusinessWrite(card, undefined, phone);
    if (!trusted.plan) delete value.plan_id;
    if (!trusted.verification) delete value.is_verified;
    return value;
  };
  let result = await supabaseAdmin.from('businesses').update(payload()).eq('id', id).select().single();
  if (missingPhoneColumn(result.error)) {
    result = await supabaseAdmin.from('businesses').update(payload(false)).eq('id', id).select().single();
  }
  return result;
}

export const createBusiness = asyncHandler(async (req, res) => {
  const user = (req as any).user;
  protectBusinessFields(req.body, null, !!(req as any).isAdmin);
  await validateCategory('', 'business', req.body.categoryId);
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
      res.status(201).json(apiSuccess({ ...toCard((await hydrateCategoryNames([result.data]))[0]), people: await loadPeople(result.data.id, true) }));
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
  const card = toCard((await hydrateCategoryNames([data]))[0]);
  delete card.themeDraft;
  const [visibleProducts,visibleServices]=await Promise.all([publicItems(data.id,'product',products),publicItems(data.id,'service',services||[])]);
  res.json(apiSuccess({
    ...card,
    sectionVisibility: { products: visibility.products, services: visibility.services, offers: visibility.special_offers, gallery: visibility.photo_gallery, events: visibility.upcoming_events },
    categories: await loadPublicCategories(visibleProducts,visibleServices),
    products: visibleProducts.map(toProduct),
    services: visibleServices.map(toService),
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
  const kinds = new Set(kind.split(','));
  const wants = (type: string) => kinds.has('all') || kinds.has(type);
  // Bulk reads replace per-business queries; page explicitly past PostgREST's row cap.
  const readPages = async (makeQuery: () => any) => {
    const rows: any[] = [];
    for (let offset = 0; ; offset += 1000) {
      const { data, error } = await makeQuery().range(offset, offset + 999);
      if (error) throw new ApiError(error.message, 400);
      rows.push(...(data || []));
      if ((data || []).length < 1000) return rows;
    }
  };
  const [data, categories] = await Promise.all([
    readPages(() => supabaseAdmin.from('businesses')
      .select('id,slug,business_name,business_name_mr,category,category_mr,owner_name_mr,logo_url,address,global_category_id,feed_name:details->businessName,feed_owner:details->ownerName,feed_category:details->category,feed_logo:details->logo,feed_address:details->address')
      .eq('is_published', true).order('updated_at', { ascending: false }).order('id')),
    loadGlobalCategories(),
  ]);
  const ids = data.map(row => row.id);
  const readChildren = async (type: string, table: string, columns: string, configure: (q: any) => any) => {
    if (!wants(type)) return [];
    const rows: any[] = [];
    // Keep IN filters below URL limits without fetching each business separately.
    for (let start = 0; start < ids.length; start += 100) {
      rows.push(...await readPages(() => configure(supabaseAdmin.from(table).select(columns)
        .in('business_id', ids.slice(start, start + 100))).order('id')));
    }
    return rows;
  };
  const [products, services, events, people] = await Promise.all([
    readChildren('product', 'products', 'id,business_id,folder_category_id,is_published,name,name_en,name_mr,description,description_en,description_mr,price,image_url,category,category_en,category_mr',
      q => q.or('is_available.is.null,is_available.eq.true').or('is_published.is.null,is_published.eq.true').order('sort_order').order('created_at', { ascending: false })),
    readChildren('service', 'services', 'id,business_id,folder_category_id,is_published,name,name_en,name_mr,details,details_en,details_mr,starting_price,cover_image,category_en,category_mr',
      q => q.or('is_published.is.null,is_published.eq.true').order('created_at', { ascending: false })),
    readChildren('event', 'events', 'id,business_id,event_name_en,event_name_mr,description_en,description_mr,event_date,start_time,venue_en,venue_mr,poster_url',
      q => q.is('deleted_at', null).eq('is_active', true).order('created_at', { ascending: false })),
    readChildren('owner', 'business_people', 'id,business_id,full_name_en,full_name_mr,designation_en,designation_mr,description_en,description_mr,profile_image_url',
      q => q.eq('is_active', true).order('display_order').order('created_at')),
  ]);
  const visibleCategories = new Set(categories.filter(c => c.available).map(c => c.id));
  const publicRows = (rows: any[]) => rows.filter(row => row.is_published !== false &&
    (!row.folder_category_id || visibleCategories.has(row.folder_category_id)));
  const group = (rows: any[], map: (row: any) => any) => {
    const groups = new Map<string, any[]>();
    for (const row of rows) {
      const items = groups.get(row.business_id) || [];
      items.push(map(row)); groups.set(row.business_id, items);
    }
    return groups;
  };
  const productGroups = group(await hydrateCategoryNames(publicRows(products), categories), toProduct);
  const serviceGroups = group(await hydrateCategoryNames(publicRows(services), categories), toService);
  const eventGroups = group(events, toEvent);
  const peopleGroups = group(people, toBusinessPerson);
  const rows = await hydrateCategoryNames(data.map(row => ({ ...row, details: {
    businessName: row.feed_name, ownerName: row.feed_owner, category: row.feed_category,
    logo: row.feed_logo, address: row.feed_address,
  } })), categories);
  const businesses = rows.map(row => {
    const card = toCard(row);
    return {
      id: row.id, slug: row.slug, businessName: card.businessName, ownerName: card.ownerName,
      category: card.category, logo: card.logo, address: card.address,
      products: productGroups.get(row.id) || [], services: serviceGroups.get(row.id) || [],
      events: eventGroups.get(row.id) || [], people: peopleGroups.get(row.id) || [],
    };
  });

  const result = businesses.flatMap((catalog: any) => {
    const { products, services, events, people, ...business } = catalog;
    const businessText = [business.businessName?.en, business.businessName?.mr, business.category?.en, business.category?.mr, business.ownerName?.en, business.ownerName?.mr].join(' ').toLowerCase();
    const matches = (item: any) => !search || [item.title?.en, item.title?.mr, item.name?.en, item.name?.mr, item.fullName?.en, item.fullName?.mr, item.designation?.en, item.designation?.mr, item.description?.en, item.description?.mr, item.category?.en, item.category?.mr, item.venue?.en, item.venue?.mr, businessText].join(' ').toLowerCase().includes(search);
    const records: any[] = [];
    if (wants('business')) {
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
    if (wants('product')) products.filter(matches).forEach((item: any) => records.push({ type: 'product', item, business }));
    if (wants('service')) services.filter(matches).forEach((item: any) => records.push({ type: 'service', item, business }));
    if (wants('event')) events.filter(matches).forEach((item: any) => records.push({ type: 'event', item, business }));
    if (wants('owner')) {
      people.filter(matches).forEach((person: any) => records.push({ type: 'owner', item: person, business }));
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
  await validateCategory(current.id, 'business', req.body.categoryId, current.global_category_id);
  const trusted = { plan: !!(req as any).isAdmin && req.body.planId !== undefined, verification: !!(req as any).isAdmin && req.body.isVerified !== undefined };
  protectBusinessFields(req.body, current, !!(req as any).isAdmin);
  const themeChanged = ['themeConfig', 'themeDraft', 'templateId', 'themeColor', 'accentColor', 'fontFamily'].some(key =>
    req.body[key] !== undefined && JSON.stringify(req.body[key]) !== JSON.stringify(current.details?.[key]),
  );
  if (themeChanged) await requirePackageFeature(current.id, 'themes');
  const merged = { ...toCard(current), ...req.body, id: current.id, slug: req.body.slug ?? current.slug };
  for (const key of ['products','services','offers','events','gallery','package']) delete merged[key];
  merged.stats = current.details?.stats || {};
  const { data, error } = await saveBusiness(current.id, merged, trusted);
  if (error) {
    if (error.code === '23505' && /slug/i.test(error.message || '')) {
      throw new ApiError('This slug is already in use. Please choose another slug.', 409);
    }
    if (/requires (?:Premium|Standard or Premium)/.test(error.message || '')) throw new ApiError(error.message, 403);
    throw new ApiError('Unable to update business information', 400);
  }
  await savePeople(current.id, req.body.people);
  const content = await loadContent(current.id, true);
  res.json(apiSuccess({ ...toCard((await hydrateCategoryNames([data]))[0]), events: content.events.map(toEvent), offers: content.offers.map(toOffer), gallery: content.gallery.map(toGallery), categories: await loadCategories(current.id), products: (await loadProducts(current.id)).map(toProduct), services: (await loadServices(current.id) || []).map(toService), people: await loadPeople(current.id, true) }));
});

export const deleteBusiness = asyncHandler(async (req, res) => {
  const user = (req as any).user;
  const { password } = deleteBusinessSchema.parse(req.body);
  const { data: current, error: findError } = await supabaseAdmin
    .from('businesses')
    .select('id, owner_id, logo_public_id')
    .eq('id', req.params.id)
    .single();
  if (findError || !current) throw new ApiError('Business not found', 404);
  if (current.owner_id !== user.id && !(req as any).isAdmin) throw new ApiError('You do not own this business', 403);

  if (!user.email) throw new ApiError('A password-based account is required to delete a business', 400);
  const verification = await createAuthClient().auth.signInWithPassword({
    email: user.email,
    password,
  });
  if (verification.error || verification.data.user?.id !== user.id) {
    throw new ApiError('Password is incorrect', 401);
  }

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
    const [products, services, visibility, people, content] = await Promise.all([loadProducts(row.id), loadServices(row.id), loadVisibility(row.id), loadPeople(row.id, true), loadContent(row.id, true)]);
    const card = toCard((await hydrateCategoryNames([row]))[0]);
    return {
      ...card,
      events: content.events.map(toEvent), offers: content.offers.map(toOffer), gallery: content.gallery.map(toGallery),
      sectionVisibility: { products: visibility.products, services: visibility.services, offers: visibility.special_offers, gallery: visibility.photo_gallery, events: visibility.upcoming_events },
      categories: await loadCategories(row.id),
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
  const pkg = await getBusinessPackage(req.params.id);
  res.json(apiSuccess({ ...pkg.usage, ...pkg }));
});

export const recordProfileView = asyncHandler(async (req, res) => {
  // Use Express's trusted address; never accept a client-supplied count or visitor ID.
  const visitorHash = createHmac('sha256', env.SUPABASE_SERVICE_ROLE_KEY)
    .update(`${req.ip || req.socket.remoteAddress}|${new Date().toISOString().slice(0, 10)}`)
    .digest('hex');
  const { data, error } = await supabaseAdmin.rpc('record_business_profile_view', {
    p_slug: req.params.slug, p_visitor_hash: visitorHash,
  });
  if (error) throw new ApiError(error.message === 'Business not found' ? error.message : 'Could not record profile view', error.message === 'Business not found' ? 404 : 503);
  res.json(apiSuccess(data));
});
