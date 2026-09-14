import { asyncHandler } from '../../utils/asyncHandler';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { supabaseAdmin } from '../../config/supabaseClient';
import { productsService, requireProduct } from './products.service';
import { cloudinaryPublicIdFromUrl, deleteCloudinaryImage } from '../../utils/cloudinaryAsset';

const requireBusinessOwner = async (businessId: string, userId: string, isAdmin = false) => {
  const { data } = await supabaseAdmin.from('businesses').select('id, owner_id').eq('id', businessId).single();
  if (!data) throw new ApiError('Business not found', 404);
  if (data.owner_id !== userId && !isAdmin) throw new ApiError('You do not own this business', 403);
};

const toProduct = (row: any) => ({
  id: row.id,
  name: { en: row.name_en ?? row.name ?? '', mr: row.name_mr ?? row.name ?? '' },
  description: { en: row.description_en ?? row.description ?? '', mr: row.description_mr ?? row.description ?? '' },
  price: Number(row.price || 0), originalPrice: row.original_price == null ? undefined : Number(row.original_price),
    image: row.image_url || '', imagePublicId: row.image_public_id || '', category: { en: row.category_en ?? row.category ?? '', mr: row.category_mr ?? row.category ?? '' },
  isAvailable: row.is_available ?? true, createdAt: row.created_at, updatedAt: row.updated_at,
});

export const createProduct = asyncHandler(async (req, res) => {
  await requireBusinessOwner(req.params.businessId, (req as any).user.id, (req as any).isAdmin);
  res.status(201).json(apiSuccess(toProduct(await productsService.create(req.params.businessId, req.body))));
});

export const listProducts = asyncHandler(async (req, res) => {
  res.json(apiSuccess((await productsService.list(req.params.businessId)).map(toProduct)));
});

export const getProduct = asyncHandler(async (req, res) => {
  res.json(apiSuccess(toProduct(await requireProduct(req.params.id))));
});

export const updateProduct = asyncHandler(async (req, res) => {
  const existing = await requireProduct(req.params.id);
  await requireBusinessOwner(existing.business_id, (req as any).user.id, (req as any).isAdmin);
  if (req.body.image !== undefined) {
    const nextPublicId = req.body.imagePublicId || cloudinaryPublicIdFromUrl(req.body.image);
    if (existing.image_public_id && existing.image_public_id !== nextPublicId) {
      await deleteCloudinaryImage(existing.image_public_id, existing.id);
    }
  }
  res.json(apiSuccess(toProduct(await productsService.update(req.params.id, req.body))));
});

export const deleteProduct = asyncHandler(async (req, res) => {
  const existing = await requireProduct(req.params.id);
  await requireBusinessOwner(existing.business_id, (req as any).user.id, (req as any).isAdmin);
  await deleteCloudinaryImage(existing.image_public_id, existing.id);
  await productsService.remove(req.params.id);
  res.status(204).send();
});
