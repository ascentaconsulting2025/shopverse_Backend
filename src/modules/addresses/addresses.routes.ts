import { Router } from 'express';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { asyncHandler } from '../../utils/asyncHandler';

const router = Router();
router.use(authGuard);
const field = (max:number) => z.string().trim().min(1).max(max);
const schema = z.object({full_name:field(120),phone_number:field(25).regex(/^\+?[\d ()-]{7,25}$/),address_line_1:field(150),address_line_2:field(150),landmark:z.string().trim().max(150).nullable(),city:field(100),state:field(100),postal_code:field(20),country:field(100),address_type:z.enum(['Home','Office','Other']),custom_label:z.string().trim().max(60).nullable(),latitude:z.number().min(-90).max(90).nullable(),longitude:z.number().min(-180).max(180).nullable(),is_default:z.boolean()}).strict().superRefine((v,ctx)=>{
 if (v.address_type==='Other' && !v.custom_label) ctx.addIssue({code:'custom',path:['custom_label'],message:'Enter a label'});
 if (/^(india|in)$/i.test(v.country) && !/^[1-9]\d{5}$/.test(v.postal_code)) ctx.addIssue({code:'custom',path:['postal_code'],message:'Enter a valid PIN code'});
 if ([v.address_line_1,v.address_line_2,v.landmark,v.city,v.state,v.postal_code,v.country].filter(Boolean).join(', ').length > 500) ctx.addIssue({code:'custom',message:'Address is too long'});
 if ((v.latitude===null)!==(v.longitude===null)) ctx.addIssue({code:'custom',message:'Both coordinates are required'});
});
router.get('/',asyncHandler(async(req,res)=>{const {data,error}=await supabaseAdmin.from('customer_addresses').select('*').eq('user_id',(req as any).user.id).order('created_at'); if(error) throw new ApiError('Unable to load addresses',503); res.json(apiSuccess(data));}));
async function save(req:any,res:any,id:string|null){const input=schema.parse(req.body); const {data,error}=await supabaseAdmin.rpc('save_customer_address',{p_user:req.user.id,p_id:id,p_data:input}); if(error){if(/Address not found/.test(error.message)) throw new ApiError('Address not found',404); throw new ApiError('Unable to save address',503);} res.json(apiSuccess(data));}
router.post('/',asyncHandler(async(req,res)=>save(req,res,null)));
router.put('/:id',asyncHandler(async(req,res)=>save(req,res,z.string().uuid().parse(req.params.id))));
router.delete('/:id',asyncHandler(async(req,res)=>{const {data,error}=await supabaseAdmin.rpc('delete_customer_address',{p_user:(req as any).user.id,p_id:z.string().uuid().parse(req.params.id)}); if(error) throw new ApiError('Unable to delete address',503); if(!data) throw new ApiError('Address not found',404); res.json(apiSuccess({deleted:true}));}));
export default router;
