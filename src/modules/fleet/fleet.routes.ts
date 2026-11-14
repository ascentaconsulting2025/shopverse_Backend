import { Router } from 'express';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { supabaseAdmin as db } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { asyncHandler } from '../../utils/asyncHandler';
import { publicRateLimiter } from '../../middlewares/rateLimiter';
const router=Router();
router.use(authGuard);
const schema=z.object({name:z.string().trim().min(1).max(80),sortRank:z.number().int().min(1).max(10000),active:z.boolean()}).strict();
router.get('/',asyncHandler(async(req,res)=>{
 let query=db.from('fleet_types').select('id,code,name,sort_rank,active').order('sort_rank').order('name');
 if(!(req as any).isAdmin) query=query.eq('active',true);
 const {data,error}=await query;if(error) throw new ApiError('Unable to load fleet types.',503);res.json(apiSuccess(data));
}));
router.get('/vehicle-labels',asyncHandler(async(req,res)=>{
 if(!(req as any).isAdmin) throw new ApiError('Super admin access required.',403);
 const {data,error}=await db.from('fleet_partner_vehicle_labels').select('fleet_type_id,vehicle_label').order('vehicle_label');
 if(error)throw new ApiError('Unable to load fleet mappings.',503);res.json(apiSuccess(data));
}));
router.post('/vehicle-labels',publicRateLimiter,asyncHandler(async(req,res)=>{
 if(!(req as any).isAdmin)throw new ApiError('Super admin access required.',403);
 const input=z.object({fleetId:z.string().uuid(),label:z.string().trim().min(1).max(80)}).strict().parse(req.body);
 const {data,error}=await db.from('fleet_partner_vehicle_labels').insert({fleet_type_id:input.fleetId,vehicle_label:input.label.toLowerCase(),created_by:(req as any).user.id}).select('fleet_type_id,vehicle_label').single();
 if(error)throw new ApiError(error.code==='23505'?'This vehicle label is already mapped.':'Unable to save fleet mapping.',error.code==='23505'?409:503);res.status(201).json(apiSuccess(data));
}));
router.delete('/vehicle-labels',publicRateLimiter,asyncHandler(async(req,res)=>{
 if(!(req as any).isAdmin)throw new ApiError('Super admin access required.',403);
 const input=z.object({fleetId:z.string().uuid(),label:z.string().trim().min(1).max(80)}).strict().parse(req.body);
 const {data,error}=await db.from('fleet_partner_vehicle_labels').delete().eq('fleet_type_id',input.fleetId).eq('vehicle_label',input.label.toLowerCase()).select('vehicle_label');
 if(error)throw new ApiError('Unable to remove fleet mapping.',503);if(!data?.length)throw new ApiError('Fleet mapping not found.',404);res.json(apiSuccess({removed:true}));
}));
router.post('/',publicRateLimiter,asyncHandler(async(req,res)=>{
 if(!(req as any).isAdmin) throw new ApiError('Super admin access required.',403);
 const input=schema.extend({code:z.string().regex(/^[a-z][a-z0-9_]{0,39}$/)}).parse(req.body);
 const {data,error}=await db.from('fleet_types').insert({code:input.code,name:input.name,sort_rank:input.sortRank,active:input.active}).select('id,code,name,sort_rank,active').single();
 if(error) throw new ApiError(error.code==='23505'?'Fleet code already exists.':'Unable to save fleet type.',error.code==='23505'?409:503);res.status(201).json(apiSuccess(data));
}));
router.put('/:id',publicRateLimiter,asyncHandler(async(req,res)=>{
 if(!(req as any).isAdmin) throw new ApiError('Super admin access required.',403);
 const id=z.string().uuid().parse(req.params.id),input=schema.parse(req.body);
 const prior=await db.from('fleet_types').select('code').eq('id',id).maybeSingle();
 if(prior.error) throw new ApiError('Unable to load fleet type.',503);
 if(!prior.data) throw new ApiError('Fleet type not found.',404);
 const {data,error}=await db.from('fleet_types').update({name:input.name,sort_rank:input.sortRank,active:input.active,updated_at:new Date().toISOString()}).eq('id',id).select('id,code,name,sort_rank,active').single();
 if(error) throw new ApiError('Unable to save fleet type.',503);res.json(apiSuccess(data));
}));
export default router;
