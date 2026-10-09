"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getBusinessUsage = exports.updateSectionVisibility = exports.getSectionVisibility = exports.listMyBusinesses = exports.deleteBusiness = exports.updateBusiness = exports.getBusinessCount = exports.getBusinessBySlug = exports.createBusiness = void 0;
const asyncHandler_1 = require("../../utils/asyncHandler");
const apiError_1 = require("../../utils/apiError");
const apiResponse_1 = require("../../utils/apiResponse");
const supabaseClient_1 = require("../../config/supabaseClient");
const business_mapper_1 = require("./business.mapper");
const generateSlug_1 = require("../../utils/generateSlug");
const business_schema_1 = require("./business.schema");
const cloudinaryAsset_1 = require("../../utils/cloudinaryAsset");
const toVisibility = (row) => ({
    products: row?.products ?? true,
    services: row?.services ?? true,
    special_offers: row?.special_offers ?? true,
    photo_gallery: row?.photo_gallery ?? true,
    upcoming_events: row?.upcoming_events ?? true,
});
async function loadVisibility(businessId) {
    const { data, error } = await supabaseClient_1.supabaseAdmin
        .from('business_section_visibility')
        .select('products, services, special_offers, photo_gallery, upcoming_events')
        .eq('business_id', businessId)
        .maybeSingle();
    if (error)
        throw new apiError_1.ApiError(error.message, 400);
    return toVisibility(data);
}
async function requireOwnedBusiness(businessId, req) {
    const { data, error } = await supabaseClient_1.supabaseAdmin.from('businesses').select('id, owner_id').eq('id', businessId).single();
    if (error || !data)
        throw new apiError_1.ApiError('Business not found', 404);
    if (data.owner_id !== req.user.id && !req.isAdmin)
        throw new apiError_1.ApiError('You do not own this business', 403);
}
const missingPhoneColumn = (error) => (error?.code === 'PGRST204' || error?.code === '42703') && /phone/i.test(error.message || '');
const toService = (row) => ({
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
const toProduct = (row) => ({
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
const toEvent = (row) => ({ id: row.id, title: { en: row.event_name_en, mr: row.event_name_mr }, eventName: { en: row.event_name_en, mr: row.event_name_mr }, description: { en: row.description_en, mr: row.description_mr }, date: row.event_date, time: row.start_time, venue: { en: row.venue_en, mr: row.venue_mr }, enquiryNo: row.enquiry_number, eventLink: row.website_url || '', photo: row.poster_url || '', image: row.poster_url || '', imagePublicId: row.poster_public_id || '', isActive: row.is_active });
const toOffer = (row) => ({ id: row.id, title: { en: row.offer_title_en, mr: row.offer_title_mr }, description: { en: row.terms_en, mr: row.terms_mr }, discountBadge: { en: row.discount_badge_en, mr: row.discount_badge_mr }, discountPercentage: row.discount_percentage == null ? undefined : Number(row.discount_percentage), couponCode: row.coupon_code, validUntil: { en: row.validity_en, mr: row.validity_mr }, imageUrl: row.image_url || '', imagePublicId: row.image_public_id || '', isActive: row.is_active });
const toGallery = (row) => ({ id: row.id, url: row.image_url, imageUrl: row.image_url, imagePublicId: row.image_public_id || '', caption: row.caption, category: row.category, sortOrder: row.sort_order, isActive: row.is_active });
async function loadProducts(businessId) {
    const { data, error } = await supabaseClient_1.supabaseAdmin.from('products').select('*').eq('business_id', businessId).order('sort_order').order('created_at', { ascending: false });
    if (error)
        throw new apiError_1.ApiError(error.message, 400);
    return data || [];
}
async function loadServices(businessId) {
    const { data, error } = await supabaseClient_1.supabaseAdmin.from('services').select('*').eq('business_id', businessId).order('created_at', { ascending: false });
    if (error)
        return null;
    return data || [];
}
async function loadContent(businessId) {
    const [events, offers, gallery] = await Promise.all([
        supabaseClient_1.supabaseAdmin.from('events').select('*').eq('business_id', businessId).eq('is_active', true).is('deleted_at', null).order('created_at', { ascending: false }),
        supabaseClient_1.supabaseAdmin.from('offers').select('*').eq('business_id', businessId).eq('is_active', true).is('deleted_at', null).order('created_at', { ascending: false }),
        supabaseClient_1.supabaseAdmin.from('gallery_photos').select('*').eq('business_id', businessId).eq('is_active', true).is('deleted_at', null).order('sort_order').order('created_at', { ascending: false }),
    ]);
    return { events: events.data || [], offers: offers.data || [], gallery: gallery.data || [] };
}
async function loadPeople(businessId, includeInactive = false) {
    let query = supabaseClient_1.supabaseAdmin.from('business_people').select('*').eq('business_id', businessId).order('display_order').order('created_at');
    if (!includeInactive)
        query = query.eq('is_active', true);
    const { data, error } = await query;
    if (error)
        throw new apiError_1.ApiError(error.message, 400);
    return (data || []).map(business_mapper_1.toBusinessPerson);
}
/** Replaces the visible leadership set without deleting history/assets. */
async function savePeople(businessId, people) {
    if (people === undefined)
        return;
    const activePrimary = people.filter((person) => person.isActive !== false && person.isPrimary);
    if (activePrimary.length > 1)
        throw new apiError_1.ApiError('Only one active primary person is allowed', 400);
    if (people.some((person) => person.isActive !== false) && activePrimary.length !== 1)
        throw new apiError_1.ApiError('Exactly one active primary person is required', 400);
    const incomingIds = people.map((person) => person.id).filter(Boolean);
    const existing = await supabaseClient_1.supabaseAdmin.from('business_people').select('id').eq('business_id', businessId);
    if (existing.error)
        throw new apiError_1.ApiError(existing.error.message, 400);
    const existingIds = new Set((existing.data || []).map((person) => person.id));
    if (incomingIds.some((id) => !existingIds.has(id)))
        throw new apiError_1.ApiError('A leadership record does not belong to this business', 400);
    // Deactivate omitted records; this is recoverable and prevents stale people from rendering.
    const omittedIds = [...existingIds].filter((id) => !incomingIds.includes(id));
    if (omittedIds.length) {
        const { error } = await supabaseClient_1.supabaseAdmin.from('business_people').update({ is_active: false, is_primary: false, updated_at: new Date().toISOString() }).in('id', omittedIds);
        if (error)
            throw new apiError_1.ApiError(error.message, 400);
    }
    // Clear an existing primary first so the partial unique index is never violated.
    const clearPrimary = await supabaseClient_1.supabaseAdmin.from('business_people').update({ is_primary: false }).eq('business_id', businessId).eq('is_primary', true);
    if (clearPrimary.error)
        throw new apiError_1.ApiError(clearPrimary.error.message, 400);
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
            ? await supabaseClient_1.supabaseAdmin.from('business_people').update(payload).eq('id', person.id).eq('business_id', businessId)
            : await supabaseClient_1.supabaseAdmin.from('business_people').insert(payload);
        if (result.error)
            throw new apiError_1.ApiError(result.error.message, 400);
    }
}
async function insertBusiness(card, ownerId) {
    let result = await supabaseClient_1.supabaseAdmin.from('businesses').insert((0, business_mapper_1.toBusinessWrite)(card, ownerId)).select().single();
    if (missingPhoneColumn(result.error)) {
        result = await supabaseClient_1.supabaseAdmin.from('businesses').insert((0, business_mapper_1.toBusinessWrite)(card, ownerId, false)).select().single();
    }
    return result;
}
async function saveBusiness(id, card) {
    let result = await supabaseClient_1.supabaseAdmin.from('businesses').update((0, business_mapper_1.toBusinessWrite)(card)).eq('id', id).select().single();
    if (missingPhoneColumn(result.error)) {
        result = await supabaseClient_1.supabaseAdmin.from('businesses').update((0, business_mapper_1.toBusinessWrite)(card, undefined, false)).eq('id', id).select().single();
    }
    return result;
}
exports.createBusiness = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const user = req.user;
    const name = typeof req.body.businessName === 'object'
        ? req.body.businessName.en || req.body.businessName.mr
        : req.body.businessName;
    const baseSlug = (0, generateSlug_1.slugify)(req.body.slug || name || 'business') || `business-${(0, generateSlug_1.uniqueSuffix)()}`;
    let lastError = null;
    for (let attempt = 0; attempt < 8; attempt += 1) {
        const slug = attempt === 0 ? baseSlug : `${baseSlug}-${(0, generateSlug_1.uniqueSuffix)()}`;
        const result = await insertBusiness({ ...req.body, slug }, user.id);
        if (!result.error) {
            await savePeople(result.data.id, req.body.people);
            res.status(201).json((0, apiResponse_1.apiSuccess)({ ...(0, business_mapper_1.toCard)(result.data), people: await loadPeople(result.data.id, true) }));
            return;
        }
        lastError = result.error;
        if (result.error.code !== '23505')
            break;
    }
    throw new apiError_1.ApiError(lastError?.message || 'Unable to create business', lastError?.code === '23505' ? 409 : 400);
});
exports.getBusinessBySlug = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const { data, error } = await supabaseClient_1.supabaseAdmin.from('businesses').select('*').eq('slug', req.params.slug).eq('is_published', true).single();
    if (error || !data)
        throw new apiError_1.ApiError('Business not found', 404);
    const [products, services, content, visibility, people] = await Promise.all([loadProducts(data.id), loadServices(data.id), loadContent(data.id), loadVisibility(data.id), loadPeople(data.id)]);
    const card = (0, business_mapper_1.toCard)(data);
    res.json((0, apiResponse_1.apiSuccess)({
        ...card,
        sectionVisibility: { products: visibility.products, services: visibility.services, offers: visibility.special_offers, gallery: visibility.photo_gallery, events: visibility.upcoming_events },
        products: products.map(toProduct),
        ...(services ? { services: services.map(toService) } : {}),
        events: content.events.map(toEvent), offers: content.offers.map(toOffer), gallery: content.gallery.map(toGallery),
        people,
    }));
});
exports.getBusinessCount = (0, asyncHandler_1.asyncHandler)(async (_req, res) => {
    const { count, error } = await supabaseClient_1.supabaseAdmin
        .from('businesses')
        .select('id', { count: 'exact', head: true })
        .eq('is_published', true);
    if (error)
        throw new apiError_1.ApiError(error.message, 400);
    res.json((0, apiResponse_1.apiSuccess)({ count: count || 0 }));
});
exports.updateBusiness = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const user = req.user;
    const { data: current, error: findError } = await supabaseClient_1.supabaseAdmin.from('businesses').select('*').eq('id', req.params.id).single();
    if (findError || !current)
        throw new apiError_1.ApiError('Business not found', 404);
    if (current.owner_id !== user.id && !req.isAdmin)
        throw new apiError_1.ApiError('You do not own this business', 403);
    const merged = { ...(0, business_mapper_1.toCard)(current), ...req.body, id: current.id, slug: req.body.slug ?? current.slug };
    const nextLogoPublicId = (0, business_mapper_1.toBusinessWrite)(merged).logo_public_id;
    if (current.logo_public_id && current.logo_public_id !== nextLogoPublicId) {
        await (0, cloudinaryAsset_1.deleteCloudinaryImage)(current.logo_public_id, current.id);
    }
    const { data, error } = await saveBusiness(current.id, merged);
    if (error) {
        if (error.code === '23505' && /slug/i.test(error.message || '')) {
            throw new apiError_1.ApiError('This slug is already in use. Please choose another slug.', 409);
        }
        throw new apiError_1.ApiError('Unable to update business information', 400);
    }
    await savePeople(current.id, req.body.people);
    res.json((0, apiResponse_1.apiSuccess)({ ...(0, business_mapper_1.toCard)(data), people: await loadPeople(current.id, true) }));
});
exports.deleteBusiness = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const user = req.user;
    const { data: current, error: findError } = await supabaseClient_1.supabaseAdmin
        .from('businesses')
        .select('id, owner_id, logo_public_id')
        .eq('id', req.params.id)
        .single();
    if (findError || !current)
        throw new apiError_1.ApiError('Business not found', 404);
    if (current.owner_id !== user.id && !req.isAdmin)
        throw new apiError_1.ApiError('You do not own this business', 403);
    const [products, services, events, gallery] = await Promise.all([
        supabaseClient_1.supabaseAdmin.from('products').select('id, image_public_id').eq('business_id', current.id),
        supabaseClient_1.supabaseAdmin.from('services').select('id, cover_image_public_id').eq('business_id', current.id),
        supabaseClient_1.supabaseAdmin.from('events').select('id, poster_public_id').eq('business_id', current.id),
        supabaseClient_1.supabaseAdmin.from('gallery_photos').select('id, image_public_id').eq('business_id', current.id),
    ]);
    const childQueryError = [products, services, events, gallery].find((result) => result.error)?.error;
    if (childQueryError)
        throw new apiError_1.ApiError(childQueryError.message, 400);
    await Promise.all([
        (0, cloudinaryAsset_1.deleteCloudinaryImage)(current.logo_public_id, current.id),
        ...(products.data || []).map((row) => (0, cloudinaryAsset_1.deleteCloudinaryImage)(row.image_public_id, row.id)),
        ...(services.data || []).map((row) => (0, cloudinaryAsset_1.deleteCloudinaryImage)(row.cover_image_public_id, row.id)),
        ...(events.data || []).map((row) => (0, cloudinaryAsset_1.deleteCloudinaryImage)(row.poster_public_id, row.id)),
        ...(gallery.data || []).map((row) => (0, cloudinaryAsset_1.deleteCloudinaryImage)(row.image_public_id, row.id)),
    ]);
    const { error } = await supabaseClient_1.supabaseAdmin.from('businesses').delete().eq('id', current.id);
    if (error)
        throw new apiError_1.ApiError(error.message, 400);
    res.json((0, apiResponse_1.apiSuccess)(null));
});
exports.listMyBusinesses = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    let query = supabaseClient_1.supabaseAdmin.from('businesses').select('*').order('created_at', { ascending: false });
    if (!req.isAdmin)
        query = query.eq('owner_id', req.user.id);
    const { data, error } = await query;
    if (error)
        throw new apiError_1.ApiError(error.message, 400);
    const cards = await Promise.all(data.map(async (row) => {
        const [products, services, visibility, people] = await Promise.all([loadProducts(row.id), loadServices(row.id), loadVisibility(row.id), loadPeople(row.id, true)]);
        const card = (0, business_mapper_1.toCard)(row);
        return {
            ...card,
            sectionVisibility: { products: visibility.products, services: visibility.services, offers: visibility.special_offers, gallery: visibility.photo_gallery, events: visibility.upcoming_events },
            products: products.map(toProduct),
            ...(services ? { services: services.map(toService) } : {}),
            people,
        };
    }));
    res.json((0, apiResponse_1.apiSuccess)(cards));
});
exports.getSectionVisibility = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    await requireOwnedBusiness(req.params.id, req);
    res.json((0, apiResponse_1.apiSuccess)(await loadVisibility(req.params.id)));
});
exports.updateSectionVisibility = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    await requireOwnedBusiness(req.params.id, req);
    const visibility = business_schema_1.sectionVisibilitySchema.parse(req.body);
    const { data, error } = await supabaseClient_1.supabaseAdmin
        .from('business_section_visibility')
        .upsert({ business_id: req.params.id, ...visibility, updated_at: new Date().toISOString() }, { onConflict: 'business_id' })
        .select('products, services, special_offers, photo_gallery, upcoming_events')
        .single();
    if (error)
        throw new apiError_1.ApiError(error.message, 400);
    res.json((0, apiResponse_1.apiSuccess)(toVisibility(data)));
});
exports.getBusinessUsage = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    await requireOwnedBusiness(req.params.id, req);
    const [products, services, offers, gallery, events] = await Promise.all([
        supabaseClient_1.supabaseAdmin.from('products').select('id', { count: 'exact', head: true }).eq('business_id', req.params.id),
        supabaseClient_1.supabaseAdmin.from('services').select('id', { count: 'exact', head: true }).eq('business_id', req.params.id),
        supabaseClient_1.supabaseAdmin.from('offers').select('id', { count: 'exact', head: true }).eq('business_id', req.params.id).eq('is_active', true).is('deleted_at', null),
        supabaseClient_1.supabaseAdmin.from('gallery_photos').select('id', { count: 'exact', head: true }).eq('business_id', req.params.id).eq('is_active', true).is('deleted_at', null),
        supabaseClient_1.supabaseAdmin.from('events').select('id', { count: 'exact', head: true }).eq('business_id', req.params.id).eq('is_active', true).is('deleted_at', null),
    ]);
    const failed = [products, services, offers, gallery, events].find((item) => item.error);
    if (failed?.error)
        throw new apiError_1.ApiError(failed.error.message, 400);
    res.json((0, apiResponse_1.apiSuccess)({ products: products.count || 0, services: services.count || 0, offers: offers.count || 0, gallery: gallery.count || 0, events: events.count || 0 }));
});
