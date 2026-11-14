import { businessDb, requireBusinessAccess } from '../business-access/access.service';
import { requirePackageFeature } from '../packages/packages.service';
import { publicItems, requireCategoryOwner, validateCategory } from '../categories/categories.service';
import { asyncHandler } from '../../utils/asyncHandler';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { supabaseAdmin } from '../../config/supabaseClient';
import { productsService, requireProduct } from './products.service';

const toProduct = (row: any) => ({
  images: row.images || [], specifications: row.specifications || {},
  id: row.id, fleetTypeId: row.fleet_type_id, categoryId: row.folder_category_id ?? null, isPublished: row.is_published !== false,
  name: { en: row.name_en ?? row.name ?? '', mr: row.name_mr ?? row.name ?? '' },
  description: { en: row.description_en ?? row.description ?? '', mr: row.description_mr ?? row.description ?? '' },
  price: row.price == null || Number(row.price) <= 0 ? undefined : Number(row.price), originalPrice: row.original_price == null || Number(row.original_price) <= 0 ? undefined : Number(row.original_price),
    image: row.image_url || '', imagePublicId: row.image_public_id || '', category: { en: row.category_en ?? row.category ?? '', mr: row.category_mr ?? row.category ?? '' },
  isAvailable: row.is_available ?? true, createdAt: row.created_at, updatedAt: row.updated_at,
});

export const createProduct = asyncHandler(async (req, res) => {
  await requireBusinessAccess(req.params.businessId, req);
  await requirePackageFeature(req.params.businessId, 'products', true);
  res.status(201).json(apiSuccess(toProduct(await productsService.create(req.params.businessId, req.body, businessDb(req)))));
});

export const listProducts = asyncHandler(async (req, res) => {
  const rows = await productsService.list(req.params.businessId);
  res.json(apiSuccess((await publicItems(req.params.businessId, 'product', rows)).map(toProduct)));
});

export const getProduct = asyncHandler(async (req, res) => {
  const item = await requireProduct(req.params.id);
  if (!(await publicItems(item.business_id, 'product', [item])).length) throw new ApiError('Item not found',404);
  res.json(apiSuccess(toProduct(item)));
});

export const updateProduct = asyncHandler(async (req, res) => {
  const existing = await requireProduct(req.params.id);
  await requireBusinessAccess(existing.business_id, req);
  if (req.body.isPublished === true && existing.is_published === false) await requirePackageFeature(existing.business_id, 'products');
  await validateCategory(existing.business_id, 'product', req.body.categoryId, existing.folder_category_id);
  const saved = await productsService.update(req.params.id, req.body, businessDb(req));
  res.json(apiSuccess(toProduct(saved)));
});

export const deleteProduct = asyncHandler(async (req, res) => {
  const existing = await requireProduct(req.params.id);
  await requireBusinessAccess(existing.business_id, req);
  await productsService.remove(req.params.id, businessDb(req));
  res.status(204).send();
});

export const manageProducts = asyncHandler(async(req,res)=>{
 await requireCategoryOwner(req.params.businessId,req);
 res.json(apiSuccess((await productsService.list(req.params.businessId,businessDb(req))).map(toProduct)));
});
