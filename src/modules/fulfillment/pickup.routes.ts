import { Router } from 'express';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { supabaseAdmin as db } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { asyncHandler } from '../../utils/asyncHandler';
import { publicRateLimiter } from '../../middlewares/rateLimiter';
import { pickupSlots } from './pickup-slots';
const router=Router();router.use(authGuard);
router.get('/settings',asyncHandler(async(req,res)=>{if(!(req as any).isAdmin)throw new ApiError('Super admin access required.',403);const {data,error}=await db.from('pickup_settings').select('lead_minutes').eq('id',true).single();if(error)throw new ApiError('Pickup settings unavailable.',503);res.json(apiSuccess(data));}));
router.put('/settings',publicRateLimiter,asyncHandler(async(req,res)=>{if(!(req as any).isAdmin)throw new ApiError('Super admin access required.',403);const input=z.object({leadMinutes:z.number().int().min(0).max(10080)}).strict().parse(req.body);const {error}=await db.from('pickup_settings').update({lead_minutes:input.leadMinutes,updated_by:(req as any).user.id,updated_at:new Date().toISOString()}).eq('id',true);if(error)throw new ApiError('Unable to save pickup settings.',503);res.json(apiSuccess(input));}));
router.get('/stores/:id/slots',publicRateLimiter,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id),q=z.object({date:z.string().regex(/^\d{4}-\d{2}-\d{2}$/)}).strict().parse(req.query);
 const [store,settings]=await Promise.all([db.from('businesses').select('id,is_published,details').eq('id',id).maybeSingle(),db.from('pickup_settings').select('lead_minutes').eq('id',true).single()]);
 if(store.error||settings.error)throw new ApiError('Unable to load pickup slots.',503);
 if(!store.data?.is_published)throw new ApiError('Store unavailable.',404);
 const details=store.data.details as any,timezone=details?.businessHours?.timezone,days=details?.businessHours?.days?.en,timings=details?.businessHours?.timings?.en;
 if(typeof timezone!=='string'||!timezone.trim())throw new ApiError('Store pickup hours or timezone need updating.',409);
 try{const slots=pickupSlots(days,timings,timezone,q.date,new Date(),settings.data.lead_minutes);res.json(apiSuccess({timezone,slots}));}catch{throw new ApiError('Store pickup hours, timezone or date are invalid.',409);}
}));
export default router;
