import { Router } from 'express';
import { deliveryDistanceTenths, deliveryCharge } from './pricing';
import { quoteDeliveryCart } from './delivery-quote';
import { configSchema } from './pricing-config';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { supabaseAdmin as db } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { asyncHandler } from '../../utils/asyncHandler';
import { publicRateLimiter } from '../../middlewares/rateLimiter';
const router=Router(); router.use(authGuard);
router.get('/settings',asyncHandler(async(req,res)=>{if(!(req as any).isAdmin)throw new ApiError('Super admin access required.',403);const {data,error}=await db.from('delivery_pricing_config').select('config,updated_at').eq('id',true).single();if(error)throw new ApiError('Unable to load delivery pricing.',503);res.json(apiSuccess(data));}));
router.put('/settings',publicRateLimiter,asyncHandler(async(req,res)=>{
 if(!(req as any).isAdmin)throw new ApiError('Super admin access required.',403);
 const input=configSchema.parse(req.body);
 const fleet=await db.from('fleet_types').select('id').in('id',input.fleetRates.map(x=>x.fleetId));
 if(fleet.error)throw new ApiError('Unable to validate fleets.',503);
 if((fleet.data||[]).length!==input.fleetRates.length)throw new ApiError('One or more fleet types are unavailable.',422);
 const result=await db.rpc('save_delivery_pricing_config',{p_actor:(req as any).user.id,p_config:input});
 if(result.error)throw new ApiError('Unable to save delivery pricing.',503);res.json(apiSuccess(input));
}));
router.get('/cart-quote',publicRateLimiter,asyncHandler(async(req,res)=>{
 const input=z.object({storeId:z.string().uuid(),addressId:z.string().uuid()}).strict().parse(req.query);
 const quote=await quoteDeliveryCart((req as any).user.id,input.storeId,input.addressId);
 res.json(apiSuccess({fleet:quote.fleet,distanceKm:quote.distanceKm,options:quote.options}));
}));
// Quote only from the buyer's saved address and the store profile; no client prices or coordinates.
router.get('/quote',asyncHandler(async(req,res)=>{
 const q=z.object({storeId:z.string().uuid(),addressId:z.string().uuid(),fleetId:z.string().uuid()}).strict().parse(req.query);
 const [store,address,fleet,settings]=await Promise.all([
  db.from('businesses').select('id,is_published,details').eq('id',q.storeId).maybeSingle(),
  db.from('customer_addresses').select('postal_code,latitude,longitude').eq('id',q.addressId).eq('user_id',(req as any).user.id).maybeSingle(),
  db.from('fleet_types').select('id,active').eq('id',q.fleetId).maybeSingle(),
  db.from('delivery_pricing_config').select('config').eq('id',true).single()
 ]);
 if(store.error||address.error||fleet.error||settings.error)throw new ApiError('Unable to calculate delivery quote.',503);
 if(!store.data?.is_published||!address.data||!fleet.data?.active)throw new ApiError('Store, address or fleet unavailable.',404);
 const cfg=configSchema.safeParse(settings.data?.config);if(!cfg.success)throw new ApiError('Delivery pricing is not configured.',503);
 const loc=(store.data.details as any)?.address;const lat=Number(loc?.latitude),lon=Number(loc?.longitude);
 if(loc?.latitude==null||loc?.longitude==null||!Number.isFinite(lat)||!Number.isFinite(lon)||Math.abs(lat)>90||Math.abs(lon)>180||address.data.latitude==null||address.data.longitude==null)throw new ApiError('Store and delivery addresses need a saved map location.',409);
 if(!cfg.data.postcodes.includes(address.data.postal_code))return res.json(apiSuccess({available:false,reason:'Delivery is unavailable for this postcode.',options:[]}));
 const distanceTenths=deliveryDistanceTenths(lat,lon,Number(address.data.latitude),Number(address.data.longitude));
 const distance=distanceTenths/10;
 if(distance>cfg.data.maxRadiusKm)return res.json(apiSuccess({available:false,reason:'Delivery is unavailable at this distance.',options:[]}));
 const rate=cfg.data.fleetRates.find(r=>r.fleetId===q.fleetId);if(!rate)throw new ApiError('Delivery rate is not configured for this fleet.',409);
 const options=Object.entries(cfg.data.speeds).filter(([,v])=>v.enabled).map(([speed,v])=>({speed,base:v.base,perKm:rate.perKm,charge:deliveryCharge(v.base,rate.perKm,distanceTenths)}));
 res.json(apiSuccess({available:options.length>0,distanceKm:distance,distanceMethod:'straight_line',options}));
}));
export default router;
