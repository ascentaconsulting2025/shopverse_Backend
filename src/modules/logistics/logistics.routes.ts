import { Router } from 'express';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { publicRateLimiter } from '../../middlewares/rateLimiter';
import { supabaseAdmin as db } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { asyncHandler } from '../../utils/asyncHandler';
const router = Router();
router.use(authGuard);
const uid = (req:any):string => req.user.id;
const id = (value:unknown) => z.string().uuid().parse(value);
const reason = z.string().trim().min(3).max(1000);
function admin(req:any) { if (!(req as any).isAdmin) throw new ApiError('Administrator access required',403); }
function checked(result:any) {
 if(result.error) {
  if(result.error.code==='P0001') throw new ApiError(result.error.message,409);
  throw new ApiError('Delivery service unavailable. Check the logistics migration and retry.',503,'LOGISTICS_SETUP_REQUIRED');
 }
 return result.data;
}
async function rpc(name:string,args:object) { return checked(await db.rpc(name,args)); }
const taskColumns='id,store_order_id,status,partner_id,assignment_type,pickup_address,pickup_lat,pickup_lon,destination_address,destination_lat,destination_lon,service_area,package_description,weight_kg,volume_litres,urgency,independent_deadline,confirmation_deadline,created_at,completed_at';
async function authorize(req:any,taskId:string) {
 const task=checked(await db.from('delivery_tasks').select(taskColumns).eq('id',taskId).maybeSingle());
 if(!task) throw new ApiError('Delivery not found',404);
 const so=checked(await db.from('marketplace_store_orders').select('id,order_id,business_id,store_order_number,business_name').eq('id',task.store_order_id).single());
 const order=checked(await db.from('marketplace_orders').select('id,customer_id,customer_name,customer_phone,order_number').eq('id',so.order_id).single());
 const business=so.business_id?checked(await db.from('businesses').select('owner_id').eq('id',so.business_id).maybeSingle()):null;
 const partner=task.partner_id?checked(await db.from('delivery_partner_profiles').select('id,user_id,full_name,phone,vehicle_type').eq('id',task.partner_id).single()):null;
 const role=(req as any).isAdmin?'admin':order.customer_id===uid(req)?'customer':business?.owner_id===uid(req)?'seller':partner?.user_id===uid(req)?'partner':null;
 if(!role) throw new ApiError('Delivery not found',404);
 return {task,so,order,partner,role};
}
router.get('/settings',asyncHandler(async(req,res)=>{admin(req);res.json(apiSuccess(checked(await db.from('delivery_settings').select('*').single())))}));
const positive=z.number().finite().positive();
const settings=z.object({enabled:z.boolean(),independent_timeout_seconds:z.number().int().min(30).max(86400),acknowledgement_timeout_seconds:z.number().int().min(30).max(3600),confirmation_timeout_seconds:z.number().int().min(60).max(604800),location_max_age_seconds:z.number().int().min(30).max(3600),max_location_accuracy_m:positive.max(5000),max_active_orders:z.number().int().min(1).max(50),search_radii_km:z.array(positive.max(500)).min(1).max(10),weights:z.object({distance:z.number().min(0).max(100),workload:z.number().min(0).max(100),route:z.number().min(0).max(100),availability:z.number().min(0).max(100),vehicle:z.number().min(0).max(100)}).strict()}).strict().refine(v=>Object.values(v.weights).reduce((a,b)=>a+b,0)===100,'Weights must total 100');
router.put('/settings',publicRateLimiter,asyncHandler(async(req,res)=>{admin(req);const input=settings.parse(req.body);await rpc('delivery_save_settings',{p_actor:uid(req),p_config:input});res.json(apiSuccess(input))}));
router.get('/admin/summary',asyncHandler(async(req,res)=>{
 admin(req);const statuses=['independent_allocation','salaried_allocation','admin_intervention','assigned','accepted','reached_pickup','picked_up','on_the_way','awaiting_customer_confirmation','completed','cancelled'];
 const counts=await Promise.all(statuses.map(async status=>{const result=await db.from('delivery_tasks').select('id',{head:true,count:'exact'}).eq('status',status);checked(result);return [status,result.count]}));
 const health=checked(await db.from('delivery_worker_health').select('*').single());
 const exceptions=await db.from('delivery_exceptions').select('id',{head:true,count:'exact'}).is('resolved_at',null);checked(exceptions);
 res.json(apiSuccess({counts:Object.fromEntries(counts),health,open_exceptions:exceptions.count}));
}));
router.get('/admin/partners/:id/config',asyncHandler(async(req,res)=>{admin(req);res.json(apiSuccess(checked(await db.from('delivery_partner_profiles').select('partner_type,max_active_orders,capacity_kg,capacity_litres,employee_id,employment_active,shift_start,shift_end').eq('id',id(req.params.id)).single())))}));
router.put('/admin/partners/:id/config',publicRateLimiter,asyncHandler(async(req,res)=>{
 admin(req);const data=z.object({partner_type:z.enum(['independent','salaried']),max_active_orders:z.number().int().min(1).max(50),capacity_kg:positive.max(10000),capacity_litres:positive.max(100000),employee_id:z.string().trim().max(100).nullable(),employment_active:z.boolean(),shift_start:z.string().datetime().nullable(),shift_end:z.string().datetime().nullable()}).strict().refine(v=>(!v.shift_start&&!v.shift_end)||(!!v.shift_start&&!!v.shift_end&&new Date(v.shift_end)>new Date(v.shift_start)),'Invalid shift').refine(v=>v.partner_type!=='salaried'||!!v.employee_id,'Employee ID required').parse(req.body);
 await rpc('delivery_configure_partner',{p_partner:id(req.params.id),p_actor:uid(req),p_data:data});res.json(apiSuccess(true));
}));
router.get('/tasks',asyncHandler(async(req,res)=>{
 const query=z.object({scope:z.enum(['admin','partner']).default('partner'),page:z.coerce.number().int().min(1).max(10000).default(1),status:z.string().max(50).optional()}).strict().parse(req.query);
 let q=db.from('delivery_tasks').select('id,store_order_id,status,service_area,package_description,urgency,created_at,completed_at,marketplace_store_orders(store_order_number,business_name)',{count:'exact'});
 if(query.scope==='admin') admin(req);else {const p=checked(await db.from('delivery_partner_profiles').select('id').eq('user_id',uid(req)).maybeSingle());if(!p)return res.json(apiSuccess({tasks:[],total:0}));q=q.eq('partner_id',p.id)}
 if(query.status==='active')q=q.not('status','in','(completed,cancelled)');else if(query.status==='history')q=q.in('status',['completed','cancelled']);else if(query.status)q=q.eq('status',query.status);
 const result=await q.order('created_at',{ascending:false}).order('id').range((query.page-1)*25,query.page*25-1);const data=checked(result);res.json(apiSuccess({tasks:data,total:result.count}));
}));
router.get('/offers',asyncHandler(async(req,res)=>res.json(apiSuccess(await rpc('delivery_offers',{p_user:uid(req)})))));
router.get('/orders/:id',asyncHandler(async(req,res)=>{
 const storeId=id(req.params.id);const so=checked(await db.from('marketplace_store_orders').select('order_id,business_id').eq('id',storeId).maybeSingle());if(!so)throw new ApiError('Order not found',404);
 const o=checked(await db.from('marketplace_orders').select('customer_id').eq('id',so.order_id).single());const b=so.business_id?checked(await db.from('businesses').select('owner_id').eq('id',so.business_id).maybeSingle()):null;
 if(!(req as any).isAdmin&&o.customer_id!==uid(req)&&b?.owner_id!==uid(req))throw new ApiError('Order not found',404);
 res.json(apiSuccess(checked(await db.from('delivery_tasks').select('id,status').eq('store_order_id',storeId).maybeSingle())));
}));
router.post('/orders/:id/select',publicRateLimiter,asyncHandler(async(req,res)=>{
 const details=z.object({pickup_address:z.string().trim().min(3).max(500),pickup_lat:z.number().min(-90).max(90),pickup_lon:z.number().min(-180).max(180),destination_lat:z.number().min(-90).max(90),destination_lon:z.number().min(-180).max(180),service_area:z.string().trim().min(1).max(200),package_description:z.string().trim().min(1).max(500),weight_kg:positive.max(10000),volume_litres:positive.max(100000),eligible_vehicles:z.array(z.string().trim().min(1).max(80)).min(1).max(20),urgency:z.enum(['standard','urgent'])}).strict().parse(req.body);
 res.json(apiSuccess(await rpc('delivery_select_order',{p_store_order:id(req.params.id),p_actor:uid(req),p_admin:!!(req as any).isAdmin,p_details:details})));
}));
router.get('/tasks/:id',asyncHandler(async(req,res)=>{
 const {task,so,order,partner,role}=await authorize(req,id(req.params.id));
 const history=checked(await db.from('delivery_status_history').select('id,event,new_status,remarks,created_at').eq('task_id',task.id).order('created_at'));
 // Customer contact is restricted to the assigned partner, seller and admin. Offers never contain it.
 const contact=role==='customer'?undefined:{name:order.customer_name,phone:order.customer_phone};
 const active=!['completed','cancelled'].includes(task.status);
 const location=partner&&active?checked(await db.from('delivery_partner_availability').select('latitude,longitude,accuracy_m,location_recorded_at').eq('partner_id',partner.id).eq('is_online',true).gte('location_recorded_at',new Date(Date.now()-300000).toISOString()).maybeSingle()):null;
 const attempts=role==='admin'?checked(await db.from('delivery_allocation_attempts').select('id,kind,status,offered_at,responded_at').eq('task_id',task.id).order('offered_at')):undefined;
 res.json(apiSuccess({...task,role,store:so,customer:contact,location,attempts,partner:partner?{full_name:partner.full_name,phone:partner.phone,vehicle_type:partner.vehicle_type}:null,history}));
}));
for(const action of ['accept','decline','confirm']) router.post(`/tasks/:id/${action}`,publicRateLimiter,asyncHandler(async(req,res)=>{
 const fn=action==='confirm'?'delivery_customer_confirm':`delivery_${action}`;
 res.json(apiSuccess(await rpc(fn,{p_task:id(req.params.id),p_user:uid(req)})));
}));
router.post('/tasks/:id/transition',publicRateLimiter,asyncHandler(async(req,res)=>{
 const data=z.object({action:z.enum(['acknowledge','reached_pickup','picked_up','on_the_way','reached_customer','reject']),reason:reason.optional()}).strict().parse(req.body);
 res.json(apiSuccess(await rpc('delivery_partner_transition',{p_task:id(req.params.id),p_user:uid(req),p_action:data.action,p_reason:data.reason||null})));
}));
router.get('/tasks/:id/candidates',asyncHandler(async(req,res)=>{admin(req);res.json(apiSuccess(await rpc('delivery_candidates',{p_task:id(req.params.id)})))}));
router.post('/tasks/:id/assign',publicRateLimiter,asyncHandler(async(req,res)=>{admin(req);const data=z.object({partner_id:z.string().uuid(),reason}).strict().parse(req.body);res.json(apiSuccess(await rpc('delivery_manual_assign',{p_task:id(req.params.id),p_partner:data.partner_id,p_actor:uid(req),p_reason:data.reason})))}));
router.post('/tasks/:id/cancel',publicRateLimiter,asyncHandler(async(req,res)=>{admin(req);const data=z.object({reason}).strict().parse(req.body);res.json(apiSuccess(await rpc('delivery_admin_cancel',{p_task:id(req.params.id),p_actor:uid(req),p_reason:data.reason})))}));
router.post('/tasks/:id/exception',publicRateLimiter,asyncHandler(async(req,res)=>{const taskId=id(req.params.id);await authorize(req,taskId);const data=z.object({reason}).strict().parse(req.body);res.json(apiSuccess(await rpc('delivery_raise_exception',{p_task:taskId,p_code:'reported_issue',p_reason:data.reason,p_actor:uid(req)})))}));
router.get('/exceptions',asyncHandler(async(req,res)=>{admin(req);res.json(apiSuccess(checked(await db.from('delivery_exceptions').select('*').is('resolved_at',null).order('created_at').limit(100))))}));
router.post('/exceptions/:id/resolve',publicRateLimiter,asyncHandler(async(req,res)=>{admin(req);const data=z.object({reason}).strict().parse(req.body);const result=checked(await db.from('delivery_exceptions').update({resolved_by:uid(req),resolved_at:new Date().toISOString(),resolution:data.reason}).eq('id',id(req.params.id)).is('resolved_at',null).select('id'));if(!result.length)throw new ApiError('Exception already resolved',409);res.json(apiSuccess(true))}));
router.get('/notifications',asyncHandler(async(req,res)=>{let q=db.from('delivery_notifications').select('id,task_id,message,created_at,read_at').order('created_at',{ascending:false}).limit(50);q=(req as any).isAdmin?q.or(`recipient_id.eq.${uid(req)},for_admin.eq.true`):q.eq('recipient_id',uid(req));res.json(apiSuccess(checked(await q)))}));
router.post('/notifications/:id/read',asyncHandler(async(req,res)=>{let q=db.from('delivery_notifications').update({read_at:new Date().toISOString()}).eq('id',id(req.params.id));q=(req as any).isAdmin?q.or(`recipient_id.eq.${uid(req)},for_admin.eq.true`):q.eq('recipient_id',uid(req));checked(await q);res.json(apiSuccess(true))}));
export default router;
