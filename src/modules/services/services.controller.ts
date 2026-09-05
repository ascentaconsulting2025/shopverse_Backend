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

export const createService = asyncHandler(async (req, res) => {
  await requireBusinessOwner(req.params.businessId, (req as any).user.id, (req as any).isAdmin);
  res.status(201).json(apiSuccess(toService(await servicesService.create(req.params.businessId, req.body))));
});

export const listServices = asyncHandler(async (req, res) => {
  res.json(apiSuccess((await servicesService.list(req.params.businessId)).map(toService)));
});

export const getService = asyncHandler(async (req, res) => {
  res.json(apiSuccess(toService(await requireService(req.params.id))));
});

export const updateService = asyncHandler(async (req, res) => {
  const existing = await requireService(req.params.id);
  await requireBusinessOwner(existing.business_id, (req as any).user.id, (req as any).isAdmin);
  res.json(apiSuccess(toService(await servicesService.update(req.params.id, req.body))));
});

export const deleteService = asyncHandler(async (req, res) => {
  const existing = await requireService(req.params.id);
  await requireBusinessOwner(existing.business_id, (req as any).user.id, (req as any).isAdmin);
  await servicesService.remove(req.params.id);
  res.status(204).send();
});
