import { supabaseAdmin as db } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { deliveryCharge, deliveryDistanceTenths } from './pricing';
import { configSchema } from './pricing-config';
export async function quoteDeliveryCart(userId:string,storeId:string,addressId:string) {
 const [cart,store,address,settings]=await Promise.all([
  db.from('customer_cart_items').select('product_id,quantity').eq('customer_id',userId),
  db.from('businesses').select('details,is_published').eq('id',storeId).maybeSingle(),
  db.from('customer_addresses').select('*').eq('id',addressId).eq('user_id',userId).maybeSingle(),
  db.from('delivery_pricing_config').select('config').eq('id',true).single()
 ]);
 if(cart.error||store.error||address.error||settings.error)throw new ApiError('Unable to calculate delivery quote.',503);
 if(!store.data?.is_published||!address.data)throw new ApiError('Store or address unavailable.',409);
 const ids=(cart.data||[]).map(x=>x.product_id);if(!ids.length)throw new ApiError('Your cart is empty.',409);
 const products=await db.from('products').select('id,business_id,fleet_type_id,is_published,is_available').in('id',ids).eq('business_id',storeId);
 if(products.error)throw new ApiError('Unable to check cart products.',503);
 if(!products.data?.length||products.data.some(x=>!x.is_published||x.is_available===false))throw new ApiError('Cart or store availability changed.',409);
 const fleetIds=[...new Set(products.data.map(x=>x.fleet_type_id))];
 const fleets=await db.from('fleet_types').select('id,name,sort_rank,active').in('id',fleetIds);
 if(fleets.error)throw new ApiError('Unable to check fleet types.',503);
 if((fleets.data||[]).length!==fleetIds.length||fleets.data?.some(f=>!f.active))throw new ApiError('A product requires an inactive fleet type. Contact the store.',409);
 const chosen=[...(fleets.data||[])].sort((a,b)=>b.sort_rank-a.sort_rank||a.id.localeCompare(b.id))[0];
 if(!chosen)throw new ApiError('A fleet type is required.',409);
 const cfg=configSchema.safeParse(settings.data?.config);if(!cfg.success)throw new ApiError('Delivery pricing is not configured.',503);
 const origin=(store.data.details as any)?.address,lat=Number(origin?.latitude),lon=Number(origin?.longitude),destination=address.data;
 if(destination.latitude==null||destination.longitude==null||!Number.isFinite(Number(destination.latitude))||!Number.isFinite(Number(destination.longitude))||Math.abs(Number(destination.latitude))>90||Math.abs(Number(destination.longitude))>180)throw new ApiError('Edit your delivery address and save its current location to calculate delivery.',409);
 if(origin?.latitude==null||origin?.longitude==null||!Number.isFinite(lat)||!Number.isFinite(lon)||Math.abs(lat)>90||Math.abs(lon)>180)throw new ApiError('This shop needs to save its location before delivery is available.',409);
 const plain=(v:any)=>typeof v==='string'?v.trim():typeof v?.en==='string'?v.en.trim():'';
 if(!plain(origin?.street)||!plain(origin?.city))throw new ApiError('Store pickup address is incomplete.',409);
 if(!cfg.data.postcodes.includes(destination.postal_code))throw new ApiError('Delivery is unavailable for this postcode.',409);
 const tenths=deliveryDistanceTenths(lat,lon,Number(destination.latitude),Number(destination.longitude));
 if(tenths/10>cfg.data.maxRadiusKm)throw new ApiError('Delivery is unavailable at this distance.',409);
 const rate=cfg.data.fleetRates.find(r=>r.fleetId===chosen.id);if(!rate)throw new ApiError('Delivery rate is not configured for this fleet.',409);
 const options=Object.entries(cfg.data.speeds).filter(([,v])=>v.enabled).map(([speed,v])=>({speed,charge:deliveryCharge(v.base,rate.perKm,tenths)}));
 return {fleet:chosen,distanceKm:tenths/10,options,origin,destination,config:cfg.data};
}
