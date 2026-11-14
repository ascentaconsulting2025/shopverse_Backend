import { Router } from 'express';
import { randomUUID } from 'crypto';
import { pickupCode,pickupCodeHash } from '../fulfillment/pickup-code';
import { pickupSlots } from '../fulfillment/pickup-slots';
import { quoteDeliveryCart } from '../fulfillment/delivery-quote';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { asyncHandler } from '../../utils/asyncHandler';
import { publicRateLimiter } from '../../middlewares/rateLimiter';

const router = Router();
router.use(authGuard);
const selection = 'id,business_id,store_order_number,business_name,status,subtotal,closing_price,fulfillment_method,pickup_start,pickup_end,pickup_timezone,pickup_store_address,delivery_fee,delivery_fleet_id,delivery_distance_km,edit_token,created_at,confirmed_at,marketplace_orders(order_number,customer_name,customer_phone,delivery_address),marketplace_order_items(product_id,product_name,quantity,unit_price),pickup_reschedule_proposals(id,pickup_start,pickup_end,timezone,status),delivery_tasks(status,partner_id)';
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
router.post('/place-delivery',publicRateLimiter,asyncHandler(async(req,res)=>{
 const input=z.object({storeId:z.string().uuid(),requestKey:z.string().uuid(),addressId:z.string().uuid(),method:z.enum(['standard_4_6h','standard_24h','urgent']),expectedFleetId:z.string().uuid(),expectedFee:z.number().finite().nonnegative().max(100000000),items:z.array(z.object({id:z.string().uuid(),quantity:z.number().int().min(1).max(999),price:z.number().nonnegative().nullable()})).min(1).max(100)}).strict().parse(req.body);
 const user=(req as any).user.id;
 const prior=await supabaseAdmin.from('marketplace_orders').select('id,delivery_address_snapshot,marketplace_store_orders(id,business_id,fulfillment_method)').eq('customer_id',user).eq('request_key',input.requestKey).maybeSingle();
 if(prior.error)throw new ApiError('Unable to check order request.',503);
 const existing=(prior.data as any)?.marketplace_store_orders?.[0];
 if(prior.data&&(!existing||existing.business_id!==input.storeId||existing.fulfillment_method!==input.method||(prior.data as any).delivery_address_snapshot?.id!==input.addressId))throw new ApiError('Request key already used.',409);
 let orderId=existing?.id,replayed=!!existing;
 if(!orderId){
  let quote:Awaited<ReturnType<typeof quoteDeliveryCart>>|null=null;
  try{quote=await quoteDeliveryCart(user,input.storeId,input.addressId);}catch(error){
   // A concurrent request may have committed after the first lookup and cleared the cart.
   const recovered=await supabaseAdmin.from('marketplace_orders').select('delivery_address_snapshot,marketplace_store_orders(id,business_id,fulfillment_method)').eq('customer_id',user).eq('request_key',input.requestKey).maybeSingle();
   if(recovered.error)throw new ApiError('Unable to check order request.',503);
   const saved=(recovered.data as any)?.marketplace_store_orders?.[0];
   if(saved&&saved.business_id===input.storeId&&saved.fulfillment_method===input.method&&(recovered.data as any).delivery_address_snapshot?.id===input.addressId){orderId=saved.id;replayed=true;}
   else throw error;
  }
  if(!orderId&&quote){
   const option=quote.options.find(x=>x.speed===input.method);if(!option)throw new ApiError('That delivery speed is unavailable.',409);
   if(quote.fleet.id!==input.expectedFleetId||Math.round(option.charge*100)!==Math.round(input.expectedFee*100))throw new ApiError('Delivery charge or fleet changed. Refresh and review the updated quote.',409);
   const result=await supabaseAdmin.rpc('place_delivery_store_request',{p_customer:user,p_store:input.storeId,p_key:input.requestKey,p_address_id:input.addressId,p_expected:input.items,p_method:input.method,p_fleet:quote.fleet.id,p_distance:quote.distanceKm,p_fee:option.charge,p_config:quote.config,p_origin:quote.origin,p_destination:quote.destination});
   if(result.error){if(/changed|unavailable|Invalid cart|Request key/i.test(result.error.message||''))throw new ApiError('Cart, address or delivery details changed. Refresh and review.',409);throw new ApiError('Unable to save delivery request.',503);}orderId=result.data.store_order_id;replayed=!!result.data.replayed;
  }
 }
 const [order,store]=await Promise.all([supabaseAdmin.from('marketplace_store_orders').select(`${selection},order_id`).eq('id',orderId).single(),supabaseAdmin.from('businesses').select('whatsapp_number,details').eq('id',input.storeId).maybeSingle()]);
 if(order.error||store.error)throw new ApiError('Request saved but details could not be loaded. Retry using the same request.',503);
 res.json(apiSuccess({order:order.data,whatsapp:store.data?.details?.whatsapp||store.data?.whatsapp_number||'',replayed}));
}));
router.post('/place-pickup',publicRateLimiter,asyncHandler(async(req,res)=>{
 const input=z.object({storeId:z.string().uuid(),requestKey:z.string().uuid(),name:z.string().trim().min(1).max(120),phone:z.string().regex(/^91[6-9]\d{9}$/),pickupStart:z.string().datetime(),items:z.array(z.object({id:z.string().uuid(),quantity:z.number().int().min(1).max(999),price:z.number().nonnegative().nullable()})).min(1).max(100)}).strict().parse(req.body);
 const user=(req as any).user.id;
 const prior=await supabaseAdmin.from('marketplace_orders').select('id,marketplace_store_orders(id,business_id,fulfillment_method,pickup_start)').eq('customer_id',user).eq('request_key',input.requestKey).maybeSingle();
 if(prior.error)throw new ApiError('Unable to check order request.',503);
 const existing=(prior.data as any)?.marketplace_store_orders?.[0];
 if(prior.data && (!existing || existing.business_id!==input.storeId || existing.fulfillment_method!=='pickup' || new Date(existing.pickup_start).getTime()!==new Date(input.pickupStart).getTime()))throw new ApiError('Request key already used.',409);
 let orderId=existing?.id;
 if(!orderId){
  const [store,settings]=await Promise.all([supabaseAdmin.from('businesses').select('details,is_published').eq('id',input.storeId).maybeSingle(),supabaseAdmin.from('pickup_settings').select('lead_minutes').eq('id',true).single()]);
  if(store.error||settings.error)throw new ApiError('Pickup service unavailable.',503);
  if(!store.data?.is_published)throw new ApiError('Store unavailable.',409);
  const details=store.data.details as any,hours=details?.businessHours,address=details?.address,tz=hours?.timezone;
  const plain=(v:any)=>typeof v==='string'?v.trim():typeof v?.en==='string'?v.en.trim():'';
  const addressText=[plain(address?.street),plain(address?.landmark),plain(address?.city),plain(address?.state),plain(address?.pincode)].filter(Boolean).join(', ');
  if(!addressText || !plain(address?.city) || !plain(address?.street) || typeof tz!=='string')throw new ApiError('Store pickup address or hours need updating.',409);
  const start=new Date(input.pickupStart);let date:string,slots:{start:string;end:string}[];
  try{date=new Intl.DateTimeFormat('en-CA',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit'}).format(start);slots=pickupSlots(hours?.days?.en,hours?.timings?.en,tz,date,new Date(),settings.data.lead_minutes);}catch{throw new ApiError('Store pickup hours or timezone are invalid.',409);}
  const selected=slots.find(slot=>new Date(slot.start).getTime()===start.getTime());if(!selected)throw new ApiError('Pickup window is no longer available.',409);
  const result=await supabaseAdmin.rpc('place_pickup_store_request',{p_customer:user,p_store:input.storeId,p_key:input.requestKey,p_name:input.name,p_phone:input.phone,p_expected:input.items,p_start:selected.start,p_end:selected.end,p_hours:hours,p_address:address,p_address_text:addressText,p_lead:settings.data.lead_minutes});
  if(result.error){if(/Pickup availability changed|Request key already used|Cart changed|Cart or price changed|Store unavailable|Invalid cart/.test(result.error.message||''))throw new ApiError('Pickup or cart details changed. Refresh and review before trying again.',409);throw new ApiError('Could not save the pickup request.',503);}
  orderId=result.data.store_order_id;
 }
 const order=await supabaseAdmin.from('marketplace_store_orders').select(`${selection},order_id`).eq('id',orderId).single();
 const store=await supabaseAdmin.from('businesses').select('whatsapp_number,details').eq('id',input.storeId).maybeSingle();
 if(order.error||store.error)throw new ApiError('Request saved but details could not be loaded. Retry using the same request.',503);
 res.json(apiSuccess({order:order.data,whatsapp:store.data?.details?.whatsapp||store.data?.whatsapp_number||'',replayed:!!existing}));
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
router.get('/mine', asyncHandler(async (req, res) => {
  const customerId = (req as any).user.id;
  const {data,error} = await supabaseAdmin.from('marketplace_orders')
    .select(`id,order_number,created_at,marketplace_store_orders(${selection},marketplace_order_status_history(previous_status,new_status,created_at))`)
    .eq('customer_id',customerId).order('created_at',{ascending:false}).limit(100);
  if(error) throw new ApiError('Unable to load your orders',503);
  res.json(apiSuccess(data || []));
}));
router.get('/confirmed', asyncHandler(async (req,res) => {
  if (!(req as any).isAdmin) throw new ApiError('Super admin access required',403);
  const {data,error} = await supabaseAdmin.from('marketplace_store_orders').select(selection).not('confirmed_at','is',null).order('confirmed_at',{ascending:false}).limit(100);
  if(error) throw new ApiError('Unable to load confirmed orders',503);
  res.json(apiSuccess(data));
}));
// The token detects stale edits without changing the public order identifier.
router.patch('/:id/pending', publicRateLimiter, asyncHandler(async (req,res) => {
  const id=z.string().uuid().parse(req.params.id);
  const input=z.object({expectedToken:z.string().uuid(),items:z.array(z.object({id:z.string().uuid(),quantity:z.number().int().min(1).max(999)}).strict()).min(1).max(100)}).strict().parse(req.body);
  if(new Set(input.items.map(item=>item.id)).size!==input.items.length) throw new ApiError('Duplicate products are not allowed.',422);
  const {data,error}=await supabaseAdmin.rpc('edit_pending_store_order',{p_order:id,p_customer:(req as any).user.id,p_expected_token:input.expectedToken,p_items:input.items});
  if(error) {
    if (/Order unavailable/.test(error.message || '')) throw new ApiError('Order not found.',404);
    if (/Order changed|Product unavailable|Store unavailable/.test(error.message || '')) throw new ApiError('Order or product availability changed. Refresh and review the order.',409);
    if (/Invalid items/.test(error.message || '')) throw new ApiError('Invalid order items.',422);
    throw new ApiError('Unable to update order.',503);
  }
  res.json(apiSuccess(data));
}));
router.get('/:id/share', asyncHandler(async(req,res) => {
  const id=z.string().uuid().parse(req.params.id);
  const orderResult=await supabaseAdmin.from('marketplace_store_orders').select(`${selection},order_id`).eq('id',id).maybeSingle();
  if(orderResult.error) throw new ApiError('Unable to load order.',503);
  const order=orderResult.data as any;
  if(!order) throw new ApiError('Order not found.',404);
  const owner=await supabaseAdmin.from('marketplace_orders').select('customer_id').eq('id',order.order_id).maybeSingle();
  if(owner.error) throw new ApiError('Unable to load order.',503);
  if(owner.data?.customer_id !== (req as any).user.id) throw new ApiError('Order not found.',404);
  const store=await supabaseAdmin.from('businesses').select('whatsapp_number,details').eq('id',order.business_id).maybeSingle();
  if(store.error) throw new ApiError('Unable to load store.',503);
  res.json(apiSuccess({order,whatsapp:store.data?.details?.whatsapp || store.data?.whatsapp_number || ''}));
}));
async function validPickupWindow(storeId:string,startValue:string) {
 const [store,settings]=await Promise.all([supabaseAdmin.from('businesses').select('details,is_published').eq('id',storeId).maybeSingle(),supabaseAdmin.from('pickup_settings').select('lead_minutes').eq('id',true).single()]);
 if(store.error||settings.error)throw new ApiError('Pickup service unavailable.',503);if(!store.data?.is_published)throw new ApiError('Store unavailable.',409);
 const hours=(store.data.details as any)?.businessHours,tz=hours?.timezone,start=new Date(startValue);let date:string,slots:{start:string;end:string}[];
 if(typeof tz!=='string'||!tz.trim())throw new ApiError('Store pickup hours or timezone are invalid.',409);
 try{date=new Intl.DateTimeFormat('en-CA',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit'}).format(start);slots=pickupSlots(hours?.days?.en,hours?.timings?.en,tz,date,new Date(),settings.data.lead_minutes);}catch{throw new ApiError('Store pickup hours or timezone are invalid.',409);}
 const slot=slots.find(s=>new Date(s.start).getTime()===start.getTime());if(!slot)throw new ApiError('Pickup window is no longer available.',409);
 return {hours,lead:settings.data.lead_minutes,slot};
}
router.post('/:id/pickup/proposals',publicRateLimiter,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id),input=z.object({pickupStart:z.string().datetime()}).strict().parse(req.body);
 const order=await supabaseAdmin.from('marketplace_store_orders').select('business_id,fulfillment_method,status').eq('id',id).maybeSingle();
 if(order.error)throw new ApiError('Unable to load order.',503);if(!order.data||order.data.fulfillment_method!=='pickup')throw new ApiError('Order not found.',404);
 const business=await supabaseAdmin.from('businesses').select('owner_id').eq('id',order.data.business_id).maybeSingle();if(business.error)throw new ApiError('Unable to check access.',503);
 if(!(req as any).isAdmin&&business.data?.owner_id!==(req as any).user.id)throw new ApiError('Order not found.',404);
 const valid=await validPickupWindow(order.data.business_id,input.pickupStart);
 const result=await supabaseAdmin.rpc('pickup_propose_window',{p_order:id,p_actor:(req as any).user.id,p_admin:!!(req as any).isAdmin,p_start:valid.slot.start,p_end:valid.slot.end,p_hours:valid.hours,p_lead:valid.lead});
 if(result.error){if(/changed|unavailable/i.test(result.error.message||''))throw new ApiError('Order or pickup availability changed.',409);throw new ApiError('Unable to propose pickup window.',503);}res.json(apiSuccess({proposalId:result.data}));
}));
router.post('/:id/pickup/proposals/:proposalId/respond',publicRateLimiter,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id),proposalId=z.string().uuid().parse(req.params.proposalId),input=z.object({accept:z.boolean()}).strict().parse(req.body);
 const order=await supabaseAdmin.from('marketplace_store_orders').select('business_id,marketplace_orders(customer_id)').eq('id',id).maybeSingle();const row=order.data as any;
 if(order.error)throw new ApiError('Unable to load order.',503);if(!row||row.marketplace_orders?.customer_id!==(req as any).user.id)throw new ApiError('Order not found.',404);
 const proposal=await supabaseAdmin.from('pickup_reschedule_proposals').select('pickup_start,status').eq('id',proposalId).eq('store_order_id',id).maybeSingle();
 if(proposal.error)throw new ApiError('Unable to load proposal.',503);if(!proposal.data||proposal.data.status!=='pending')throw new ApiError('Pickup proposal changed.',409);
 const valid=input.accept?await validPickupWindow(row.business_id,proposal.data.pickup_start):null;
 const result=await supabaseAdmin.rpc('pickup_respond_window',{p_order:id,p_proposal:proposalId,p_customer:(req as any).user.id,p_accept:input.accept,p_hours:valid?.hours||null,p_lead:valid?.lead??null});
 if(result.error)throw new ApiError('Unable to respond to pickup proposal.',503);if(result.data==='unavailable')throw new ApiError('Order not found.',404);if(result.data==='changed')throw new ApiError('Order or pickup availability changed.',409);res.json(apiSuccess({status:result.data}));
}));
router.post('/:id/pickup/switch',publicRateLimiter,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id),input=z.object({pickupStart:z.string().datetime()}).strict().parse(req.body);
 const order=await supabaseAdmin.from('marketplace_store_orders').select('business_id,marketplace_orders(customer_id)').eq('id',id).maybeSingle(),row=order.data as any;
 if(order.error)throw new ApiError('Unable to load order.',503);if(!row||row.marketplace_orders?.customer_id!==(req as any).user.id)throw new ApiError('Order not found.',404);
 const valid=await validPickupWindow(row.business_id,input.pickupStart);
 const store=await supabaseAdmin.from('businesses').select('details').eq('id',row.business_id).single();if(store.error)throw new ApiError('Store unavailable.',503);
 const address=(store.data.details as any)?.address;
 const plain=(v:any)=>typeof v==='string'?v.trim():typeof v?.en==='string'?v.en.trim():'';
 if(!plain(address?.street)||!plain(address?.city))throw new ApiError('Store pickup address is incomplete.',409);
 const result=await supabaseAdmin.rpc('switch_delivery_to_pickup',{p_order:id,p_customer:(req as any).user.id,p_start:valid.slot.start,p_end:valid.slot.end,p_hours:valid.hours,p_address:address,p_lead:valid.lead});
 if(result.error)throw new ApiError('Unable to switch to pickup.',503);if(result.data!=='switched')throw new ApiError(result.data==='assigned'?'A delivery partner has now been assigned.':'Pickup is not available for this order.',409);res.json(apiSuccess({switched:true}));
}));
function pickupSecret():string {const secret=process.env.PICKUP_CODE_SECRET || '';if(secret.length<32)throw new ApiError('Pickup handover is not configured.',503);return secret;}
router.post('/:id/pickup/ready',publicRateLimiter,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id),secret=pickupSecret(),nonce=randomUUID(),code=pickupCode(secret,id,nonce);
 const {data,error}=await supabaseAdmin.rpc('pickup_mark_ready',{p_order:id,p_actor:(req as any).user.id,p_admin:!!(req as any).isAdmin,p_nonce:nonce,p_hash:pickupCodeHash(secret,id,code)});
 if(error)throw new ApiError('Unable to mark pickup ready.',503);if(data==='unavailable')throw new ApiError('Order not found.',404);if(!['ready','already_ready'].includes(data))throw new ApiError('Pickup is not ready for this action.',409);res.json(apiSuccess({ready:true}));
}));
router.get('/:id/pickup/code',publicRateLimiter,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id),secret=pickupSecret();
 const order=await supabaseAdmin.from('marketplace_store_orders').select('status,fulfillment_method,marketplace_orders(customer_id)').eq('id',id).maybeSingle();
 if(order.error)throw new ApiError('Unable to load pickup code.',503);const row=order.data as any;
 if(!row||row.fulfillment_method!=='pickup'||row.marketplace_orders?.customer_id!==(req as any).user.id)throw new ApiError('Order not found.',404);
 if(row.status!=='READY_FOR_DISPATCH')throw new ApiError('Pickup code is not available yet.',409);
 const saved=await supabaseAdmin.from('pickup_handover_codes').select('nonce,expires_at,consumed_at').eq('store_order_id',id).maybeSingle();
 if(saved.error)throw new ApiError('Unable to load pickup code.',503);if(!saved.data||saved.data.consumed_at||new Date(saved.data.expires_at).getTime()<=Date.now())throw new ApiError('Pickup code expired. Ask the store for a new code.',409);
 res.set('Cache-Control','no-store');res.json(apiSuccess({code:pickupCode(secret,id,saved.data.nonce),expiresAt:saved.data.expires_at}));
}));
router.post('/:id/pickup/verify',publicRateLimiter,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id),input=z.object({code:z.string().regex(/^\d{6}$/)}).strict().parse(req.body),secret=pickupSecret();
 const {data,error}=await supabaseAdmin.rpc('pickup_verify_handover',{p_order:id,p_actor:(req as any).user.id,p_admin:!!(req as any).isAdmin,p_hash:pickupCodeHash(secret,id,input.code)});
 if(error)throw new ApiError('Unable to verify pickup.',503);if(data==='unavailable')throw new ApiError('Order not found.',404);
 if(data==='locked')throw new ApiError('Too many attempts. Try again in 15 minutes.',429);if(data==='expired')throw new ApiError('Pickup code expired. Generate a new one.',409);if(data==='invalid_code')throw new ApiError('Incorrect pickup code.',422);if(data!=='completed')throw new ApiError('Pickup is not ready for verification.',409);
 res.json(apiSuccess({completed:true}));
}));
router.post('/:id/confirm', asyncHandler(async (req,res) => {
  const id=z.string().uuid().parse(req.params.id);
  const input=z.object({expectedToken:z.string().uuid(),closingPrice:z.number().finite().positive().max(9999999999.99).refine(v=>Math.abs(v*100-Math.round(v*100))<0.000001,'Maximum two decimal places'),fleetId:z.string().uuid().optional()}).strict().parse(req.body || {});
  const {data,error}=await supabaseAdmin.rpc('confirm_fulfillment_order',{p_order:id,p_actor:(req as any).user.id,p_admin:(req as any).isAdmin === true,p_token:input.expectedToken,p_price:input.closingPrice,p_fleet:input.fleetId||null});
  if(error && /Order changed/.test(error.message || '')) throw new ApiError('Order changed. Refresh and review the latest details before confirming.',409);
  if(error && /Delivery address unavailable/.test(error.message || '')) throw new ApiError('The store or customer address is unavailable for delivery. Update the address before confirming.',409);
  if(error && /Fleet unavailable|Fleet rate unavailable/.test(error.message || '')) throw new ApiError('Select an active fleet with a configured delivery rate.',409);
  if(error && /Invalid closing price|Product subtotal unavailable/.test(error.message || '')) throw new ApiError('Enter an agreed closing price greater than zero and no more than the complete product subtotal.',422);
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
