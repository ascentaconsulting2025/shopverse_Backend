import { asyncHandler } from '../../utils/asyncHandler';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { supabaseAdmin } from '../../config/supabaseClient';
import { contentService, requireContent } from './content.service';

type Kind = 'events' | 'offers' | 'gallery';
const requireOwner = async (businessId: string, req: any) => {
  const { data } = await supabaseAdmin.from('businesses').select('id, owner_id').eq('id', businessId).single();
  if (!data) throw new ApiError('Business not found', 404);
  if (data.owner_id !== req.user.id && !req.isAdmin) throw new ApiError('You do not own this business', 403);
};
const mapRow = (kind: Kind, row: any) => kind === 'events' ? ({ id: row.id, title: { en: row.event_name_en, mr: row.event_name_mr }, eventName: { en: row.event_name_en, mr: row.event_name_mr }, description: { en: row.description_en, mr: row.description_mr }, date: row.event_date, time: row.start_time, venue: { en: row.venue_en, mr: row.venue_mr }, enquiryNo: row.enquiry_number, eventLink: row.website_url || '', photo: row.poster_url || '', image: row.poster_url || '', isActive: row.is_active }) : kind === 'offers' ? ({ id: row.id, title: { en: row.offer_title_en, mr: row.offer_title_mr }, description: { en: row.terms_en, mr: row.terms_mr }, discountBadge: { en: row.discount_badge_en, mr: row.discount_badge_mr }, discountPercentage: row.discount_percentage == null ? undefined : Number(row.discount_percentage), couponCode: row.coupon_code, validUntil: { en: row.validity_en, mr: row.validity_mr }, isActive: row.is_active }) : ({ id: row.id, url: row.image_url, imageUrl: row.image_url, caption: row.caption, category: row.category, sortOrder: row.sort_order, isActive: row.is_active });
export const makeContentController = (kind: Kind) => ({
  create: asyncHandler(async (req, res) => { await requireOwner(req.params.businessId, req); res.status(201).json(apiSuccess(mapRow(kind, await contentService.create(kind, req.params.businessId, req.body)))); }),
  list: asyncHandler(async (req, res) => { const result = await contentService.list(kind, req.params.businessId, req.query); res.json(apiSuccess({ ...result, items: result.items.map(row => mapRow(kind, row)) })); }),
  get: asyncHandler(async (req, res) => res.json(apiSuccess(mapRow(kind, await requireContent(kind, req.params.id))))),
  update: asyncHandler(async (req, res) => { const current = await requireContent(kind, req.params.id); await requireOwner(current.business_id, req); res.json(apiSuccess(mapRow(kind, await contentService.update(kind, req.params.id, req.body)))); }),
  remove: asyncHandler(async (req, res) => { const current = await requireContent(kind, req.params.id); await requireOwner(current.business_id, req); await contentService.remove(kind, req.params.id); res.status(204).send(); }),
});