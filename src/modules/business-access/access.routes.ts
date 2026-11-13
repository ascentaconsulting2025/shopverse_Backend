import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { asyncHandler } from '../../utils/asyncHandler';
import { apiSuccess } from '../../utils/apiResponse';
import { ApiError } from '../../utils/apiError';
import { supabaseAdmin } from '../../config/supabaseClient';
import { accessError, businessAccessEnabled, businessDb, deliverInvitation, hashInvitation, invitationDeliveryConfig, newInvitationToken, requireBusinessAccess } from './access.service';

const router = Router();
const uuid = z.string().uuid();
const email = z.string().trim().toLowerCase().email().max(254);
const limiter = rateLimit({windowMs:15*60*1000,limit:40,standardHeaders:true,legacyHeaders:false});
router.get('/business-access/config',authGuard,(_req,res)=>res.json(apiSuccess({enabled:businessAccessEnabled()})));
router.use(['/business-access','/businesses/:businessId/access','/business-invitations'],authGuard,asyncHandler(async(_req,_res,next)=>{
 if(!businessAccessEnabled()) throw new ApiError('Business access management is not enabled',503);
 next();
}));
async function rpc(req: any,name: string,args: any) {
 const result=await businessDb(req).rpc(name,args);
 if(result.error) accessError(result.error);
 return result.data;
}
router.post('/business-access/users/search',limiter,asyncHandler(async(req,res)=>{
 const q=z.object({email,businessId:uuid.optional()}).strict().parse(req.body);
 // Owner searches are contextual; global account discovery remains admin-only.
 if(!q.businessId && !(req as any).isAdmin) throw new ApiError('Administrator required',403);
 res.json(apiSuccess(await rpc(req,'business_find_user',{p_business:q.businessId||null,p_email:q.email})));
}));
router.get('/businesses/:businessId/access/check',asyncHandler(async(req,res)=>{
 const role=await requireBusinessAccess(uuid.parse(req.params.businessId),req);
 res.json(apiSuccess({role}));
}));
router.get('/businesses/:businessId/access',asyncHandler(async(req,res)=>{
 const details=await rpc(req,'business_access_details',{p_business:uuid.parse(req.params.businessId)});
 let invitationsAvailable=true;try{invitationDeliveryConfig();}catch{invitationsAvailable=false;}
 res.json(apiSuccess({...details,invitationsAvailable}));
}));
router.post('/businesses/:businessId/access/change',limiter,asyncHandler(async(req,res)=>{
 const input=z.object({action:z.enum(['assign_owner','transfer_owner','add_manager','remove_manager']),targetUserId:uuid,
 expectedOwnerId:uuid.nullable(),previousOwner:z.enum(['remove','manager']),pendingInvitations:z.enum(['revoke','keep']),confirmed:z.literal(true)}).strict().parse(req.body);
 if(['assign_owner','add_manager'].includes(input.action) && !(req as any).isAdmin) throw new ApiError('Administrator required',403);
 await rpc(req,'business_change_access',{p_business:uuid.parse(req.params.businessId),p_action:input.action,p_target:input.targetUserId,
 p_expected_owner:input.expectedOwnerId,p_previous_owner:input.previousOwner,p_pending_invitations:input.pendingInvitations});
 res.json(apiSuccess({updated:true}));
}));
router.post('/businesses/:businessId/access/invitations',limiter,asyncHandler(async(req,res)=>{
 const bid=uuid.parse(req.params.businessId); const input=z.object({email}).strict().parse(req.body);
 await requireBusinessAccess(bid,req,true);
 invitationDeliveryConfig();
 const days=z.coerce.number().int().min(1).max(30).parse(process.env.BUSINESS_INVITATION_DAYS||7);
 const token=newInvitationToken();
 const id=await rpc(req,'business_invite',{p_business:bid,p_email:input.email,p_hash:hashInvitation(token),p_days:days});
 try {
  await deliverInvitation(id,input.email,token);
  const saved=await supabaseAdmin.from('business_invitations').update({delivery_status:'sent'}).eq('id',id);
  if(saved.error) throw new ApiError('Delivery status could not be saved. Reload before trying again.',503);
 } catch {
  await supabaseAdmin.from('business_invitations').update({delivery_status:'failed'}).eq('id',id);
  throw new ApiError('Invitation saved, but email delivery could not be confirmed. Revoke it before retrying.',502,'BUSINESS_INVITATION_DELIVERY_FAILED');
 }
 res.status(201).json(apiSuccess({id}));
}));
router.delete('/businesses/:businessId/access/invitations/:invitationId',asyncHandler(async(req,res)=>{
 await rpc(req,'business_revoke_invitation',{p_business:uuid.parse(req.params.businessId),p_invitation:uuid.parse(req.params.invitationId)});
 res.json(apiSuccess({revoked:true}));
}));
router.get('/business-invitations',asyncHandler(async(req,res)=>{res.json(apiSuccess(await rpc(req,'business_my_invitations',{})));}));
router.post('/business-invitations/accept',limiter,asyncHandler(async(req,res)=>{
 const input=z.object({token:z.string().regex(/^[A-Za-z0-9_-]{43}$/)}).strict().parse(req.body);
 const businessId=await rpc(req,'business_accept_invitation',{p_hash:hashInvitation(input.token)});
 res.json(apiSuccess({businessId}));
}));
export default router;
