import { requirePackageFeature } from '../packages/packages.service';
import { asyncHandler } from '../../utils/asyncHandler';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { supabaseAdmin } from '../../config/supabaseClient';
import { contentService, requireContent } from './content.service';
import { cloudinaryPublicIdFromUrl, deleteCloudinaryImage, deleteUnreferencedCloudinaryImage } from '../../utils/cloudinaryAsset';

type Kind = 'events' | 'offers' | 'gallery';
const requireOwner = async (businessId: string, req: any) => {
  const { data } = await supabaseAdmin.from('businesses').select('id, owner_id').eq('id', businessId).single();
  if (!data) throw new ApiError('Business not found', 404);
  if (data.owner_id !== req.user.id && !req.isAdmin) throw new ApiError('You do not own this business', 403);
};
const requirePublished = async (businessId: string) => {
  const { data } = await supabaseAdmin.from('businesses').select('is_published').eq('id', businessId).single();
  if (!data?.is_published) throw new ApiError('Business not found', 404);
};
const mapRow = (kind: Kind, row: any) => kind === 'events' ? ({ id: row.id, title: { en: row.event_name_en, mr: row.event_name_mr }, eventName: { en: row.event_name_en, mr: row.event_name_mr }, description: { en: row.description_en, mr: row.description_mr }, date: row.event_date, time: row.start_time, venue: { en: row.venue_en, mr: row.venue_mr }, enquiryNo: row.enquiry_number, eventLink: row.website_url || '', photo: row.poster_url || '', image: row.poster_url || '', imagePublicId: row.poster_public_id || '', isActive: row.is_active, active: row.is_active !== false }) : kind === 'offers' ? ({ id: row.id, title: { en: row.offer_title_en, mr: row.offer_title_mr }, description: { en: row.terms_en, mr: row.terms_mr }, discountBadge: { en: row.discount_badge_en, mr: row.discount_badge_mr }, discountPercentage: row.discount_percentage == null ? undefined : Number(row.discount_percentage), couponCode: row.coupon_code || undefined, validUntil: { en: row.validity_en ?? '', mr: row.validity_mr ?? '' }, imageUrl: row.image_url || '', imagePublicId: row.image_public_id || '', isActive: row.is_active, active: row.is_active !== false }) : ({ id: row.id, url: row.image_url, imageUrl: row.image_url, imagePublicId: row.image_public_id || '', caption: row.caption, category: row.category, sortOrder: row.sort_order, isActive: row.is_active, active: row.is_active !== false });
export const makeContentController = (kind: Kind) => ({
  create: asyncHandler(async (req, res) => { await requireOwner(req.params.businessId, req); await requirePackageFeature(req.params.businessId, kind, req.body.isActive !== false); res.status(201).json(apiSuccess(mapRow(kind, await contentService.create(kind, req.params.businessId, req.body)))); }),
  list: asyncHandler(async (req, res) => { await requirePublished(req.params.businessId); const result = await contentService.list(kind, req.params.businessId, { ...req.query, active: 'true' }); res.json(apiSuccess({ ...result, items: result.items.map(row => mapRow(kind, row)) })); }),
  get: asyncHandler(async (req, res) => { const current = await requireContent(kind, req.params.id); await requirePublished(current.business_id); if (!current.is_active) throw new ApiError('Item not found', 404); res.json(apiSuccess(mapRow(kind, current))); }),
  update: asyncHandler(async (req, res) => {
    const current = await requireContent(kind, req.params.id);
    await requireOwner(current.business_id, req);
    if (req.body.isActive === true && current.is_active === false) await requirePackageFeature(current.business_id, kind, true);
    const imageField = kind === 'events' ? req.body.photo ?? req.body.image : kind === 'gallery' ? req.body.url ?? req.body.imageUrl : undefined;
    let replacedImagePublicId: string | null = null;
    if (imageField !== undefined) {
      const nextPublicId = req.body.imagePublicId || cloudinaryPublicIdFromUrl(imageField);
      const currentPublicId = kind === 'events' ? current.poster_public_id : current.image_public_id;
      if (currentPublicId && currentPublicId !== nextPublicId) {
        replacedImagePublicId = currentPublicId;
      }
    }
    const updated = await contentService.update(kind, req.params.id, req.body);
    if (replacedImagePublicId) {
      deleteUnreferencedCloudinaryImage(replacedImagePublicId, current.id).catch((error) =>
        console.error('Cloudinary cleanup failed after content image update', {
          contentId: current.id,
          publicId: replacedImagePublicId,
          error: error instanceof Error ? error.message : error,
        }),
      );
    }
    res.json(apiSuccess(mapRow(kind, updated)));
  }),
  remove: asyncHandler(async (req, res) => {
    const current = await requireContent(kind, req.params.id);
    await requireOwner(current.business_id, req);
    const publicId = kind === 'events' ? current.poster_public_id : kind === 'gallery' ? current.image_public_id : null;
    await deleteCloudinaryImage(publicId, current.id);
    await contentService.remove(kind, req.params.id);
    res.status(204).send();
  }),
});
