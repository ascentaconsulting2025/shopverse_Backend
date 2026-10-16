import { Router } from 'express';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { asyncHandler } from '../../utils/asyncHandler';
import { apiSuccess } from '../../utils/apiResponse';
import { ApiError } from '../../utils/apiError';
import { supabaseAdmin } from '../../config/supabaseClient';
import { loadCategories, requireCategoryOwner } from './categories.service';
const router = Router();
const scope = z.object({businessId:z.string().uuid(),type:z.enum(['product','service'])});
const fields = z.object({name:z.string().trim().min(1).max(100),name_mr:z.string().trim().max(100).optional(),image_url:z.union([z.literal(''),z.string().url().regex(/^https?:\/\//)]).default(''),is_published:z.boolean().default(true),display_order:z.number().int().min(0).default(0)});
router.use('/:businessId/categories/:type',authGuard,asyncHandler(async(req,_res,next)=>{
 scope.parse(req.params); await requireCategoryOwner(req.params.businessId,req); next();
}));
router.get('/:businessId/categories/:type',asyncHandler(async(req,res)=>{
 res.json(apiSuccess((await loadCategories(req.params.businessId)).filter(c=>c.type===req.params.type)));
}));
router.post('/:businessId/categories/:type',asyncHandler(async(req,res)=>{
 const {data,error}=await supabaseAdmin.from('business_categories').insert({...fields.parse(req.body),business_id:req.params.businessId,type:req.params.type}).select().single();
 if(error) throw new ApiError(error.message,400); res.status(201).json(apiSuccess(data));
}));
router.post('/:businessId/categories/:type/move',asyncHandler(async(req,res)=>{
 const body=z.object({ids:z.array(z.string().uuid()).min(1).max(500).refine(ids=>new Set(ids).size===ids.length),categoryId:z.string().uuid().nullable()}).parse(req.body);
 const {error}=await supabaseAdmin.rpc('move_category_items',{p_business:req.params.businessId,p_type:req.params.type,p_ids:body.ids,p_category:body.categoryId});
 if(error) throw new ApiError(error.message,400); res.json(apiSuccess(null));
}));
router.post('/:businessId/categories/:type/reorder',asyncHandler(async(req,res)=>{
 const {ids}=z.object({ids:z.array(z.string().uuid()).max(500)}).parse(req.body);
 const {error}=await supabaseAdmin.rpc('reorder_categories',{p_business:req.params.businessId,p_type:req.params.type,p_ids:ids});
 if(error) throw new ApiError(error.message,400); res.json(apiSuccess(null));
}));
router.patch('/:businessId/categories/:type/:id' ,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id);
 const {data,error}=await supabaseAdmin.from('business_categories').update({...fields.partial().parse(req.body),updated_at:new Date().toISOString()}).eq('id',id).eq('business_id',req.params.businessId).eq('type',req.params.type).select().maybeSingle();
 if(error) throw new ApiError(error.message,400); if(!data) throw new ApiError('Category not found',404); res.json(apiSuccess(data));
}));
router.delete('/:businessId/categories/:type/:id',asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id);
 const {data,error}=await supabaseAdmin.from('business_categories').delete().eq('id',id).eq('business_id',req.params.businessId).eq('type',req.params.type).select('id').maybeSingle();
 if(error) throw new ApiError(error.message,400); if(!data) throw new ApiError('Category not found',404); res.status(204).send();
}));
export default router;
