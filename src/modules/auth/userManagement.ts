import { z } from 'zod';
import rateLimit from 'express-rate-limit';
import { supabaseAdmin, createAuthClient } from '../../config/supabaseClient';
import { asyncHandler } from '../../utils/asyncHandler';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';

const admins = () => (process.env.ADMIN_EMAILS || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
export async function audit(actor: string | null, target: string | null, action: string, outcome: string) {
 const {error} = await supabaseAdmin.from('user_management_audit').insert({actor_id:actor,target_id:target,action,outcome});
 if(error) throw new ApiError('Account audit service unavailable',503);
}
export const requireSuperAdmin = asyncHandler(async(req,res,next) => {
 if(!(req as any).isAdmin) {
  await audit((req as any).user.id,null,'management_access','rejected');
  throw new ApiError('Super Admin access required',403);
 }
 next();
});
export const recoveryLimiter = rateLimit({windowMs:15*60*1000,limit:10,standardHeaders:true,legacyHeaders:false,message:{success:false,error:{message:'Too many password reset attempts. Try again in 15 minutes.'}}});
const querySchema = z.object({
 search:z.string().trim().max(120).default(''),role:z.enum(['','admin','user']).default(''),status:z.enum(['','active','inactive']).default(''),
 from:z.string().datetime().optional(),to:z.string().datetime().optional(),sort:z.enum(['name','created_at','last_login']).default('created_at'),
 direction:z.enum(['asc','desc']).default('desc'),page:z.coerce.number().int().min(1).max(1000000).default(1)
});
export const listUsers = asyncHandler(async(req,res) => {
 const q=querySchema.parse(req.query);
 const {data,error}=await supabaseAdmin.rpc('management_users',{admin_emails:admins(),search_text:q.search,role_filter:q.role,status_filter:q.status,date_from:q.from,date_to:q.to,sort_key:q.sort,descending:q.direction==='desc',page_number:q.page});
 if(error) throw new ApiError('Could not load users. Check the user-management migration.',503);
 res.json(apiSuccess(data));
});
async function getTarget(id: string) {
 z.string().uuid().parse(id);
 const {data,error}=await supabaseAdmin.rpc('management_users',{admin_emails:admins(),target:id});
 if(error) throw new ApiError('Could not load account',503);
 if(!data?.users?.[0]) throw new ApiError('User not found',404);
 return data.users[0];
}
export const userDetails = asyncHandler(async(req,res) => {
 const user=await getTarget(req.params.id);
 const page=z.coerce.number().int().min(1).max(1000000).default(1).parse(req.query.page);
 const {data,error,count}=await supabaseAdmin.from('user_management_audit').select('id,actor_id,target_id,action,outcome,created_at',{count:'exact'}).eq('target_id',user.id).order('created_at',{ascending:false}).range((page-1)*25,page*25-1);
 if(error) throw new ApiError('Could not load audit history',503);
 res.json(apiSuccess({user,audit:data,audit_total:count}));
});
export const mutateUser = asyncHandler(async(req,res) => {
 const input=z.discriminatedUnion('action',[
  z.object({action:z.literal('profile'),full_name:z.string().trim().min(1).max(120)}).strict(),
  z.object({action:z.enum(['activate','deactivate','reset']),confirmed:z.literal(true)}).strict()
 ]).parse(req.body);
 const user=await getTarget(req.params.id); const actor=(req as any).user.id;
 if(user.role==='admin' || user.id===actor) {
  await audit(actor,user.id,input.action,'rejected');
  throw new ApiError('Super Admin accounts are protected. Manage them through the identity provider.',403);
 }
 if(input.action==='profile') {
  const {error}=await supabaseAdmin.rpc('management_update_profile',{actor,target:user.id,new_name:input.full_name});
  if(error) throw new ApiError('Could not update profile',503);
 } else {
  if(input.action==='reset' && (!user.email_verified || user.status!=='active')) throw new ApiError('Recovery requires an active account with a confirmed email',409);
  let redirectTo:string|undefined;
  if(input.action==='reset') {
   redirectTo=process.env.PASSWORD_RESET_URL;
   if(!redirectTo || !/^https:\/\//.test(redirectTo) && !/^http:\/\/localhost[:/]/.test(redirectTo)) throw new ApiError('Email recovery is not configured',503);
  }
  await audit(actor,user.id,input.action,'requested');
  try {
   const result=input.action==='reset'
    ? await createAuthClient().auth.resetPasswordForEmail(user.email,{redirectTo})
    : await supabaseAdmin.auth.admin.updateUserById(user.id,{ban_duration:input.action==='deactivate'?'876000h':'none'});
   if(result.error) throw new Error('provider failure');
  } catch {
   await audit(actor,user.id,input.action,'failed');
   throw new ApiError('Authentication provider could not complete the request. Please retry.',502);
  }
  await audit(actor,user.id,input.action,'success');
 }
 res.json(apiSuccess({message:input.action==='reset'?'Recovery email accepted for delivery. The user must open the link to choose a new password.':'Account updated'}));
});
export const completeRecovery = asyncHandler(async(req,res) => {
 const input=z.object({token_hash:z.string().min(20).max(512),password:z.string().min(8).max(128)}).strict().parse(req.body);
 const client=createAuthClient();
 const {data,error}=await client.auth.verifyOtp({token_hash:input.token_hash,type:'recovery'});
 if(error || !data.user || !data.session) {
  await audit(null,null,'password_reset','failed');
  throw new ApiError('Recovery link is invalid or expired. Request a new link.',400);
 }
 try {
  const result=await client.auth.updateUser({password:input.password});
  if(result.error) {
   await audit(data.user.id,data.user.id,'password_reset','failed');
   throw new ApiError('Password was not accepted. Check the password policy and request a new recovery link.',400);
  }
  await audit(data.user.id,data.user.id,'password_reset','success');
 } finally { await client.auth.signOut({scope:'global'}); }
 res.json(apiSuccess({message:'Password updated. Sign in with your new password.'}));
});
