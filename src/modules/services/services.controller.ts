import { requirePackageFeature } from '../packages/packages.service';
import { publicItems, requireCategoryOwner, validateCategory } from '../categories/categories.service';
import { asyncHandler } from '../../utils/asyncHandler';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { supabaseAdmin } from '../../config/supabaseClient';
import { requireService, servicesService } from './services.service';

const requireBusinessOwner = async (businessId: string, userId: string, isAdmin = false) => {
  const { data } = await supabaseAdmin.from('businesses').select('id, owner_id').eq('id', businessId).single();
  if (!data) throw new ApiError('Business not found', 404);
  if (data.owner_id !== userId && !isAdmin) throw new ApiError('You do not own this business', 403);
};

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

export const createService = asyncHandler(async (req, res) => {
  await requireBusinessOwner(req.params.businessId, (req as any).user.id, (req as any).isAdmin);
  await requirePackageFeature(req.params.businessId, 'services', true);
  res.status(201).json(apiSuccess(toService(await servicesService.create(req.params.businessId, req.body))));
});

export const listServices = asyncHandler(async (req, res) => {
  const rows = await servicesService.list(req.params.businessId);
  res.json(apiSuccess((await publicItems(req.params.businessId, 'service', rows)).map(toService)));
});

export const getService = asyncHandler(async (req, res) => {
  const item = await requireService(req.params.id);
  if (!(await publicItems(item.business_id, 'service', [item])).length) throw new ApiError('Item not found',404);
  res.json(apiSuccess(toService(item)));
});

export const updateService = asyncHandler(async (req, res) => {
  const existing = await requireService(req.params.id);
  await requireBusinessOwner(existing.business_id, (req as any).user.id, (req as any).isAdmin);
  if (req.body.isPublished === true && existing.is_published === false) await requirePackageFeature(existing.business_id, 'services');
  await validateCategory(existing.business_id, 'service', req.body.categoryId, existing.folder_category_id);
  const saved = await servicesService.update(req.params.id, req.body);
  res.json(apiSuccess(toService(saved)));
});

export const deleteService = asyncHandler(async (req, res) => {
  const existing = await requireService(req.params.id);
  await requireBusinessOwner(existing.business_id, (req as any).user.id, (req as any).isAdmin);
  await servicesService.remove(req.params.id);
  res.status(204).send();
});

export const manageServices = asyncHandler(async(req,res)=>{
 await requireCategoryOwner(req.params.businessId,req);
 res.json(apiSuccess((await servicesService.list(req.params.businessId)).map(toService)));
});
