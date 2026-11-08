import { Router } from 'express';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { asyncHandler } from '../../utils/asyncHandler';
import { publicRateLimiter } from '../../middlewares/rateLimiter';

const router = Router();
router.use(authGuard);
const selection = 'id,store_order_number,business_name,status,subtotal,created_at,confirmed_at,marketplace_orders(order_number,customer_name,customer_phone,delivery_address),marketplace_order_items(product_name,quantity,unit_price)';
router.post('/place', publicRateLimiter, asyncHandler(async(req,res) => {
  const common={storeId:z.string().uuid(),requestKey:z.string().uuid(),items:z.array(z.object({id:z.string().uuid(),quantity:z.number().int().min(1).max(999),price:z.number().nonnegative().nullable()})).min(1).max(100)};
  // Preserve retries created by older clients while new requests use a saved address.
  const input=z.union([z.object({...common,addressId:z.string().uuid()}).strict(),z.object({...common,name:z.string().trim().min(1).max(120),phone:z.string().regex(/^91[6-9]\d{9}$/),address:z.string().trim().min(1).max(500)}).strict()]).parse(req.body);
  const result='addressId' in input
    ? await supabaseAdmin.rpc('place_saved_address_request',{p_customer:(req as any).user.id,p_store:input.storeId,p_key:input.requestKey,p_address_id:input.addressId,p_expected:input.items})
    : await supabaseAdmin.rpc('place_whatsapp_store_request',{p_customer:(req as any).user.id,p_store:input.storeId,p_key:input.requestKey,p_name:input.name,p_phone:input.phone,p_address:input.address,p_expected:input.items});
  if(result.error) {
    if (/Address unavailable/.test(result.error.message || '')) throw new ApiError('Address no longer available. Select another address.',409);
    if (/Cart changed|Cart or price changed|Store unavailable|Invalid cart/.test(result.error.message || '')) throw new ApiError('Cart, price or store availability changed. Refresh your cart and review it before trying again.',409);
    if (result.error.code === 'PGRST202') throw new ApiError('Ordering is not configured yet. Please contact the shop administrator.',503,'ORDER_SETUP_REQUIRED');
    throw new ApiError('Could not save the order request',503);
  }
  const {data:order,error}=await supabaseAdmin.from('marketplace_store_orders').select(`${selection},business_id,order_id`).eq('id',result.data.store_order_id).maybeSingle();
  if(error || !order) throw new ApiError('Request saved but details could not be loaded. Retry using the same request.',503);
  const customer=await supabaseAdmin.from('marketplace_orders').select('customer_id').eq('id',(order as any).order_id).maybeSingle();
  if(customer.error || customer.data?.customer_id !== (req as any).user.id) throw new ApiError('Request unavailable',403);
  const store=await supabaseAdmin.from('businesses').select('whatsapp_number,details').eq('id',input.storeId).maybeSingle();
  if(store.error) throw new ApiError('Request saved but store details could not be loaded. Retry.',503);
  res.json(apiSuccess({order,whatsapp:store.data?.details?.whatsapp || store.data?.whatsapp_number || '',replayed:result.data.replayed}));
}));
router.get('/store/:businessId', asyncHandler(async (req, res) => {
  const id = z.string().uuid().parse(req.params.businessId);
  const {data: business, error: lookupError} = await supabaseAdmin.from('businesses').select('owner_id').eq('id',id).maybeSingle();
  if (lookupError) throw new ApiError('Unable to check store access',503);
  if (!business || (business.owner_id !== (req as any).user.id && !(req as any).isAdmin)) throw new ApiError('Store access denied',403);
  const {data,error} = await supabaseAdmin.from('marketplace_store_orders').select(selection).eq('business_id',id).order('created_at',{ascending:false}).limit(100);
  if(error) throw new ApiError('Unable to load orders',503);
  res.json(apiSuccess(data));
}));
router.get('/confirmed', asyncHandler(async (req,res) => {
  if (!(req as any).isAdmin) throw new ApiError('Super admin access required',403);
  const {data,error} = await supabaseAdmin.from('marketplace_store_orders').select(selection).not('confirmed_at','is',null).order('confirmed_at',{ascending:false}).limit(100);
  if(error) throw new ApiError('Unable to load confirmed orders',503);
  res.json(apiSuccess(data));
}));
router.post('/:id/confirm', asyncHandler(async (req,res) => {
  const id=z.string().uuid().parse(req.params.id);
  const {data,error}=await supabaseAdmin.rpc('manage_store_order',{p_order:id,p_actor:(req as any).user.id,p_is_admin:(req as any).isAdmin === true,p_action:'accept'});
  if(error) throw new ApiError('Unable to confirm order',503);
  if(!data) throw new ApiError('Order not found, access denied, or no longer pending',409);
  res.json(apiSuccess({confirmed:true}));
}));
router.post('/:id/reject', asyncHandler(async (req,res) => {
  const id=z.string().uuid().parse(req.params.id);
  const {data,error}=await supabaseAdmin.rpc('manage_store_order',{p_order:id,p_actor:(req as any).user.id,p_is_admin:(req as any).isAdmin === true,p_action:'reject'});
  if(error) throw new ApiError('Unable to reject order',503);
  if(!data) throw new ApiError('Order not found, access denied, or no longer pending',409);
  res.json(apiSuccess({rejected:true}));
}));
export default router;
