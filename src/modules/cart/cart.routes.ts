import { Router } from 'express';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { asyncHandler } from '../../utils/asyncHandler';

const router = Router();
router.use(authGuard);
router.get('/', asyncHandler(async (req, res) => {
  const { data: rows, error } = await supabaseAdmin.from('customer_cart_items').select('product_id,quantity').eq('customer_id', (req as any).user.id).order('updated_at');
  if (error) throw new ApiError('Unable to load cart', 503);
  const ids = (rows || []).map(row => row.product_id);
  const result = ids.length ? await supabaseAdmin.from('explore_products').select('*').in('id', ids) : { data: [], error: null };
  if (result.error) throw new ApiError('Unable to load products', 503);
  const products = new Map((result.data || []).map((product: any) => [product.id, product]));
  res.json(apiSuccess((rows || []).map(row => ({ ...row, product: products.get(row.product_id) || null }))));
}));
router.post('/', asyncHandler(async (req, res) => {
  const { productId } = z.object({ productId: z.string().uuid() }).parse(req.body);
  const { data, error } = await supabaseAdmin.from('explore_products').select('id,available').eq('id', productId).maybeSingle();
  if (error) throw new ApiError('Unable to check product', 503);
  if (!data || data.available === false) throw new ApiError('Product is unavailable', 409);
  const saved = await supabaseAdmin.rpc('cart_add_item', { p_customer: (req as any).user.id, p_product: productId });
  if (saved.error) throw new ApiError('Unable to add product to cart', 503);
  res.json(apiSuccess({ added: true }));
}));
router.patch('/:id', asyncHandler(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  const { quantity } = z.object({ quantity: z.number().int().min(1).max(999) }).parse(req.body);
  const { error } = await supabaseAdmin.from('customer_cart_items').update({ quantity, updated_at: new Date().toISOString() }).eq('customer_id', (req as any).user.id).eq('product_id', id);
  if (error) throw new ApiError('Unable to update cart', 503);
  res.json(apiSuccess({ updated: true }));
}));
router.delete('/:id', asyncHandler(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  const { error } = await supabaseAdmin.from('customer_cart_items').delete().eq('customer_id', (req as any).user.id).eq('product_id', id);
  if (error) throw new ApiError('Unable to remove product', 503);
  res.json(apiSuccess({ removed: true }));
}));
export default router;
