import { categoryDeletionPreview } from './deletion-preview';
import { normalizeName, validateWrite } from './integrity';
import { Router } from 'express';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { asyncHandler } from '../../utils/asyncHandler';
import { apiSuccess } from '../../utils/apiResponse';
import { ApiError } from '../../utils/apiError';
import { supabaseAdmin } from '../../config/supabaseClient';
import { categoryError, loadCategoryArchitecture, loadCategories, loadGlobalCategories, loadMappings, requireCategoryOwner } from './categories.service';
import { parseCategoryImport } from './import';
export const categoryFields = z.object({
 name:z.string().trim().min(1).max(100).transform(value=>value.normalize('NFKC').replace(/\s+/gu,' ')),
 name_mr:z.string().trim().max(100).transform(value=>value.normalize('NFKC').replace(/\s+/gu,' ')).optional(),
 parent_id:z.string().uuid().nullable().optional(),
 image_url:z.union([z.literal(''),z.string().url().regex(/^https?:\/\//)]).optional(),
 icon:z.string().trim().min(1).max(80).optional(),
 catalog_kind:z.enum(['legacy','business','product','service']).optional(),
 status:z.enum(['enabled','disabled']).optional(),
}).strict();
const version=z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
export const requireCategoryAdmin=asyncHandler(async(req,_res,next)=>{
 if(!(req as any).isAdmin) throw new ApiError('Only Super Admin can manage global categories',403);
 next();
});
export const globalCategoryRoutes=Router();
globalCategoryRoutes.use(authGuard);
globalCategoryRoutes.get('/',asyncHandler(async(req,res)=>{
 const query=z.object({available:z.enum(['true','false']).optional(),search:z.string().trim().max(100).optional()}).parse(req.query);
 let rows=await loadGlobalCategories();
 if(query.available) rows=rows.filter(row=>row.available===(query.available==='true'));
 if(query.search) rows=rows.filter(row=>(row.name+' '+row.name_mr).toLowerCase().includes(query.search!.toLowerCase()));
 res.json(apiSuccess(rows));
}));
globalCategoryRoutes.post('/import',requireCategoryAdmin,asyncHandler(async(req,res)=>{
 const body=z.object({structure:z.unknown(),preview:z.boolean(),kind:z.enum(['legacy','product','service']).optional()}).strict().parse(req.body);
 const paths=parseCategoryImport(body.structure);
 const catalog=await loadCategoryArchitecture();
 const kind=body.kind||'legacy';
 for(const path of paths){
  let parent_id:string|null=null;
  for(let index=0;index<path.length;index++){
   const existing=catalog.find(c=>c.catalog_kind===kind && (c.parent_id||null)===parent_id && normalizeName(c.name)===normalizeName(path[index]));
   if(existing){path[index]=existing.name;parent_id=existing.id;continue;}
   const fields:{name:string;catalog_kind:string;parent_id:string|null}={name:path[index],catalog_kind:kind,parent_id};
   validateWrite(catalog,fields);
   const node:any={...fields,id:`import-${catalog.length}`,business_category_ids:catalog.find(c=>c.id===parent_id)?.business_category_ids||[]};
   catalog.push(node);parent_id=node.id;
  }
 }
 const {data,error}=body.kind
  ? await supabaseAdmin.rpc('import_catalog_categories',{p_paths:paths,p_preview:body.preview,p_kind:body.kind})
  : await supabaseAdmin.rpc('import_global_categories',{p_paths:paths,p_preview:body.preview});
 if(error) categoryError(error);
 res.json(apiSuccess(data));
}));
const mappingBody=z.object({type:z.enum(['product','service']),categoryIds:z.array(z.string().uuid()).max(1000).refine(ids=>new Set(ids).size===ids.length)}).strict();
globalCategoryRoutes.get('/architecture',requireCategoryAdmin,asyncHandler(async(_req,res)=>{res.json(apiSuccess(await loadCategoryArchitecture()));}));
globalCategoryRoutes.get('/:id/deletion-preview',requireCategoryAdmin,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id);
 const {offset}=z.object({offset:z.coerce.number().int().min(0).max(1000000).default(0)}).parse(req.query);
 res.json(apiSuccess(await categoryDeletionPreview(id,offset)));
}));
globalCategoryRoutes.get('/:id/impact',requireCategoryAdmin,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id);
 const {data,error}=await supabaseAdmin.rpc('catalog_category_impact',{p_id:id});
 if(error) categoryError(error);
 res.json(apiSuccess(data));
}));
globalCategoryRoutes.get('/:id/mappings',requireCategoryAdmin,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id);
 const category=(await loadGlobalCategories()).find(c=>c.id===id && c.catalog_kind==='business');
 if(!category) throw new ApiError('Business category not found',404);
 res.json(apiSuccess({categoryIds:await loadMappings(id),version:category.version}));
}));
globalCategoryRoutes.post('/:id/mappings/preview',requireCategoryAdmin,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id);
 const body=mappingBody.parse(req.body);
 const {data,error}=await supabaseAdmin.rpc('catalog_assignment_impact',{p_business_category:id,p_type:body.type,p_categories:body.categoryIds});
 if(error) categoryError(error);
 res.json(apiSuccess(data));
}));
globalCategoryRoutes.put('/:id/mappings',requireCategoryAdmin,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id);
 const body=mappingBody.extend({version}).parse(req.body);
 const {data,error}=await supabaseAdmin.rpc('replace_business_catalog_mappings',{p_business_category:id,p_type:body.type,p_categories:body.categoryIds,p_version:body.version});
 if(error) categoryError(error);
 res.json(apiSuccess(data));
}));
globalCategoryRoutes.get('/:id',asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id);
 const row=(await loadGlobalCategories()).find(c=>c.id===id);
 if(!row) throw new ApiError('Category not found',404);
 res.json(apiSuccess(row));
}));
globalCategoryRoutes.post('/',requireCategoryAdmin,asyncHandler(async(req,res)=>{
 const {allow_similar=false,...fields}=categoryFields.extend({map_business_category_id:z.string().uuid().optional(),allow_similar:z.boolean().optional()}).parse(req.body);
 validateWrite(await loadCategoryArchitecture(),fields,undefined,fields.map_business_category_id,allow_similar);
 const {data,error}=await supabaseAdmin.rpc('write_global_category',{p_id:null,p_version:null,p_fields:fields,p_delete:false});
 if(error) categoryError(error);
 res.status(201).json(apiSuccess(data));
}));
globalCategoryRoutes.patch('/:id',requireCategoryAdmin,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id);
 const {version:expected,business_category_id,allow_similar=false,...fields}=categoryFields.partial().extend({version,business_category_id:z.string().uuid().optional(),allow_similar:z.boolean().optional()}).strict().parse(req.body);
 validateWrite(await loadCategoryArchitecture(),fields,id,business_category_id,allow_similar);
 if(!Object.keys(fields).length) throw new ApiError('No category changes supplied',400);
 const {data,error}=await supabaseAdmin.rpc('write_global_category',{p_id:id,p_version:expected,p_fields:fields,p_delete:false});
 if(error) categoryError(error);
 res.json(apiSuccess(data));
}));
globalCategoryRoutes.delete('/:id',requireCategoryAdmin,asyncHandler(async(req,res)=>{
 const id=z.string().uuid().parse(req.params.id);
 const body=z.object({version}).strict().parse(req.body);
 const rows=await loadCategoryArchitecture();
 if(rows.some(c=>c.parent_id===id))throw new ApiError('Remove or move child categories before deleting this category',409);
 if((rows.find(c=>c.id===id)?.business_category_ids.length||0)>1)throw new ApiError('This category is shared. Remove its business mapping instead of deleting it globally.',409);
 const {error}=await supabaseAdmin.rpc('write_global_category',{p_id:id,p_version:body.version,p_fields:{},p_delete:true});
 if(error) categoryError(error);
 res.status(204).send();
}));

// Retain owner item moves and old read URLs during rollout. Category CRUD is global.
const router=Router();
const scope=z.object({businessId:z.string().uuid(),type:z.enum(['product','service'])});
router.use('/:businessId/categories/:type',authGuard,asyncHandler(async(req,_res,next)=>{
 scope.parse(req.params); await requireCategoryOwner(req.params.businessId,req); next();
}));
router.get('/:businessId/categories/:type',asyncHandler(async(req,res)=>{
 res.json(apiSuccess((await loadCategories(req.params.businessId)).filter(c=>c.type===req.params.type)));
}));
router.post('/:businessId/categories/:type/assignment-preview',asyncHandler(async(req,res)=>{
 const body=z.object({categoryId:z.string().uuid()}).strict().parse(req.body);
 const {data,error}=await supabaseAdmin.rpc('catalog_assignment_impact',{p_business_category:body.categoryId,p_business:req.params.businessId});
 if(error) categoryError(error);
 res.json(apiSuccess(data));
}));
router.post('/:businessId/categories/:type/move',asyncHandler(async(req,res)=>{
 const body=z.object({ids:z.array(z.string().uuid()).min(1).max(500).refine(ids=>new Set(ids).size===ids.length),categoryId:z.string().uuid()}).strict().parse(req.body);
 const {error}=await supabaseAdmin.rpc('move_category_items',{p_business:req.params.businessId,p_type:req.params.type,p_ids:body.ids,p_category:body.categoryId});
 if(error) categoryError(error);
 res.json(apiSuccess(null));
}));
router.all('/:businessId/categories/:type',requireCategoryAdmin,(_req,_res,next)=>next(new ApiError('Use Category Architecture Desk to manage global categories',410)));
router.all('/:businessId/categories/:type/:id',requireCategoryAdmin,(_req,_res,next)=>next(new ApiError('Use Category Architecture Desk to manage global categories',410)));
export default router;
