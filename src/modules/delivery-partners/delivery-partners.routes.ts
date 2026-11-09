import multer from 'multer';
import { randomUUID } from 'node:crypto';
import { imageDimensions } from '../../utils/imageDimensions';
import { uploadsRateLimiter } from '../../middlewares/rateLimiter';
import { Router } from 'express';
import { z } from 'zod';
import { authGuard } from '../../middlewares/authGuard';
import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { asyncHandler } from '../../utils/asyncHandler';
import { publicRateLimiter } from '../../middlewares/rateLimiter';

const router = Router();
const documentUpload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024, files: 1 } });
router.use(authGuard);
const optionalText = (max: number) => z.string().trim().max(max).nullable();
// Full replacement of editable draft fields; approval and identity documents are separate operations.
const draftSchema = z.object({
  full_name: optionalText(120), phone: optionalText(25), email: z.union([z.string().trim().email().max(254), z.literal(''), z.null()]),
  current_address: optionalText(500), city: optionalText(100), service_area: optionalText(200),
  emergency_contact: optionalText(200), vehicle_type: optionalText(80), vehicle_registration: optionalText(80),
  vehicle_capacity: optionalText(200),
}).strict();

router.get('/me', asyncHandler(async (req, res) => {
  const { data, error } = await supabaseAdmin.from('delivery_partner_profiles').select('*').eq('user_id', (req as any).user.id).maybeSingle();
  if (error) throw new ApiError('Unable to load delivery partner profile', 503);
  res.json(apiSuccess(data));
}));
router.put('/me', publicRateLimiter, asyncHandler(async (req, res) => {
  const parsed = draftSchema.safeParse(req.body);
  if (!parsed.success) {
    const labels: Record<string, string> = { full_name: 'Full name', phone: 'Mobile number', email: 'Email', current_address: 'Current address', city: 'City', service_area: 'Service area', emergency_contact: 'Emergency contact', vehicle_type: 'Vehicle type', vehicle_registration: 'Vehicle registration', vehicle_capacity: 'Vehicle capacity' };
    const fields = [...new Set(parsed.error.issues.map(issue => labels[String(issue.path[0])]).filter(Boolean))];
    throw new ApiError(fields.length ? `Check the format or length of: ${fields.join(', ')}.` : 'Invalid application details', 400);
  }
  const input = parsed.data;
  const { data, error } = await supabaseAdmin.rpc('save_delivery_partner_draft', { p_user: (req as any).user.id, p_data: input });
  if (error) {
    if (error.message.includes('Application is not editable')) throw new ApiError('This application cannot currently be edited', 409);
    throw new ApiError('Unable to save delivery partner draft', 503);
  }
  res.json(apiSuccess(data));
}));
router.get('/me/operational-state', asyncHandler(async (req, res) => {
  const profile = await supabaseAdmin.from('delivery_partner_profiles').select('id,verification_status').eq('user_id', (req as any).user.id).maybeSingle();
  if (profile.error) throw new ApiError('Unable to load partner status', 503);
  if (!profile.data || profile.data.verification_status !== 'approved') throw new ApiError('Approved profile required', 403);
  const state = await supabaseAdmin.from('delivery_partner_availability').select('is_online,latitude,longitude,accuracy_m,location_recorded_at').eq('partner_id', profile.data.id).maybeSingle();
  if (state.error) throw new ApiError('Unable to load availability', 503);
  res.json(apiSuccess(state.data || { is_online: false, latitude: null, longitude: null, accuracy_m: null, location_recorded_at: null }));
}));
async function updateState(req: any, res: any, input: { online: boolean | null; latitude: number | null; longitude: number | null; accuracy: number | null }) {
  const { data, error } = await supabaseAdmin.rpc('set_delivery_partner_operational_state', { p_user: req.user.id, p_online: input.online, p_lat: input.latitude, p_lon: input.longitude, p_accuracy: input.accuracy });
  if (error) {
    if (/Approved profile required|Availability managed by admin|An active shift is required to go online|Go online before sharing location/.test(error.message)) throw new ApiError(error.message, 403);
    throw new ApiError('Unable to update availability', 503);
  }
  res.json(apiSuccess(data));
}
router.put('/me/availability', publicRateLimiter, asyncHandler(async (req, res) => {
  const { online } = z.object({ online: z.boolean() }).strict().parse(req.body);
  await updateState(req, res, { online, latitude: null, longitude: null, accuracy: null });
}));
router.post('/me/location', publicRateLimiter, asyncHandler(async (req, res) => {
  const input = z.object({ latitude: z.number().finite().min(-90).max(90), longitude: z.number().finite().min(-180).max(180), accuracy: z.number().finite().nonnegative() }).strict().parse(req.body);
  await updateState(req, res, { online: null, ...input });
}));
router.post('/me/submit', publicRateLimiter, asyncHandler(async (req, res) => {
  const { data, error } = await supabaseAdmin.rpc('submit_delivery_partner_application', { p_user: (req as any).user.id });
  if (error) {
    if (/Application cannot be submitted|Complete required application details|Identity document required/.test(error.message)) throw new ApiError(error.message, 409);
    throw new ApiError('Unable to submit application', 503);
  }
  res.json(apiSuccess(data));
}));
router.get('/admin/overview', asyncHandler(async (req, res) => {
  if (!(req as any).isAdmin) throw new ApiError('Super admin access required', 403);
  const [all, pending, approved, independentOnline, salariedOnline] = await Promise.all([
    supabaseAdmin.from('delivery_partner_profiles').select('id', { count: 'exact', head: true }),
    supabaseAdmin.from('delivery_partner_profiles').select('id', { count: 'exact', head: true }).in('verification_status', ['pending_verification', 'under_review']),
    supabaseAdmin.from('delivery_partner_profiles').select('id', { count: 'exact', head: true }).eq('verification_status', 'approved'),
    supabaseAdmin.from('delivery_partner_availability').select('partner_id,delivery_partner_profiles!inner(partner_type,verification_status)', { count: 'exact', head: true }).eq('is_online', true).eq('delivery_partner_profiles.partner_type', 'independent').eq('delivery_partner_profiles.verification_status', 'approved'),
    supabaseAdmin.from('delivery_partner_availability').select('partner_id,delivery_partner_profiles!inner(partner_type,verification_status)', { count: 'exact', head: true }).eq('is_online', true).eq('delivery_partner_profiles.partner_type', 'salaried').eq('delivery_partner_profiles.verification_status', 'approved'),
  ]);
  if ([all, pending, approved, independentOnline, salariedOnline].some(result => result.error)) throw new ApiError('Unable to load logistics overview', 503);
  res.json(apiSuccess({ partners: all.count, pending: pending.count, approved: approved.count, independent_online: independentOnline.count, salaried_online: salariedOnline.count }));
}));
router.get('/admin/partners', asyncHandler(async (req, res) => {
  if (!(req as any).isAdmin) throw new ApiError('Super admin access required', 403);
  const query = z.object({ page: z.coerce.number().int().min(1).max(10000).default(1), type: z.enum(['independent','salaried']).optional(), status: z.enum(['draft','pending_verification','under_review','additional_information_required','approved','rejected','suspended','deactivated']).optional() }).strict().parse(req.query);
  let request = supabaseAdmin.from('delivery_partner_profiles').select('id,full_name,city,service_area,vehicle_type,partner_type,verification_status,created_at', { count: 'exact' });
  if (query.type) request = request.eq('partner_type', query.type);
  if (query.status) request = request.eq('verification_status', query.status);
  const { data, error, count } = await request.order('created_at', { ascending: false }).order('id', { ascending: false }).range((query.page - 1) * 25, query.page * 25 - 1);
  if (error) throw new ApiError('Unable to load partners', 503);
  res.json(apiSuccess({ partners: data || [], total: count, page: query.page }));
}));
router.post('/admin/partners/:id/status', publicRateLimiter, asyncHandler(async (req, res) => {
  if (!(req as any).isAdmin) throw new ApiError('Super admin access required', 403);
  const id = z.string().uuid().parse(req.params.id);
  const input = z.object({ action: z.enum(['suspend', 'reactivate']), reason: z.string().trim().min(1).max(1000) }).strict().parse(req.body);
  const { data, error } = await supabaseAdmin.rpc('manage_delivery_partner_status', { p_partner: id, p_actor: (req as any).user.id, p_action: input.action, p_reason: input.reason });
  if (error) {
    if (/Partner not found|Partner status changed/.test(error.message)) throw new ApiError(error.message, 409);
    throw new ApiError('Unable to update partner status', 503);
  }
  res.json(apiSuccess(data));
}));
router.get('/admin/applications', asyncHandler(async (req, res) => {
  if (!(req as any).isAdmin) throw new ApiError('Super admin access required', 403);
  const { data, error } = await supabaseAdmin.from('delivery_partner_profiles').select('id,full_name,phone,email,city,service_area,vehicle_type,vehicle_registration,vehicle_capacity,verification_status,created_at').in('verification_status', ['pending_verification','under_review']).order('updated_at').limit(100);
  if (error) throw new ApiError('Unable to load applications', 503);
  res.json(apiSuccess(data || []));
}));
router.post('/admin/applications/:id/review', publicRateLimiter, asyncHandler(async (req, res) => {
  if (!(req as any).isAdmin) throw new ApiError('Super admin access required', 403);
  const id = z.string().uuid().parse(req.params.id);
  const input = z.object({ decision: z.enum(['approved','rejected','additional_information_required']), reason: z.string().trim().max(1000) }).strict().refine(v => v.decision === 'approved' || v.reason.length > 0, { message: 'Reason required' }).parse(req.body);
  const { data, error } = await supabaseAdmin.rpc('review_delivery_partner_application', { p_partner: id, p_actor: (req as any).user.id, p_decision: input.decision, p_reason: input.reason });
  if (error) {
    if (/Application is not awaiting review|Identity document required/.test(error.message)) throw new ApiError(error.message, 409);
    throw new ApiError('Unable to review application', 503);
  }
  res.json(apiSuccess(data));
}));
router.get('/me/documents', asyncHandler(async (req, res) => {
  const profile = await supabaseAdmin.from('delivery_partner_profiles').select('id').eq('user_id',(req as any).user.id).maybeSingle();
  if (profile.error) throw new ApiError('Unable to load documents',503);
  if (!profile.data) return res.json(apiSuccess([]));
  const docs = await supabaseAdmin.from('delivery_partner_documents').select('id,document_type,created_at').eq('partner_id',profile.data.id).order('created_at',{ascending:false});
  if (docs.error) throw new ApiError('Unable to load documents',503);
  res.json(apiSuccess(docs.data || []));
}));
router.post('/me/documents/identity', uploadsRateLimiter, documentUpload.single('document'), asyncHandler(async (req, res) => {
  const file = req.file;
  if (!file || !['image/jpeg','image/png'].includes(file.mimetype) || !imageDimensions(file.buffer) || (file.mimetype === 'image/jpeg' ? file.buffer[0] !== 0xff : file.buffer[0] !== 0x89)) throw new ApiError('Upload a valid JPG or PNG image', 400);
  const profile = await supabaseAdmin.from('delivery_partner_profiles').select('id,partner_type,verification_status').eq('user_id', (req as any).user.id).maybeSingle();
  if (profile.error) throw new ApiError('Unable to load application', 503);
  if (!profile.data || profile.data.partner_type !== 'independent' || !['draft','additional_information_required'].includes(profile.data.verification_status)) throw new ApiError('Save an editable application first', 409);
  const path = `${profile.data.id}/${randomUUID()}`;
  const uploaded = await supabaseAdmin.storage.from('delivery-partner-documents').upload(path, file.buffer, { contentType: file.mimetype, upsert: false });
  if (uploaded.error) throw new ApiError('Unable to upload document', 503);
  const registered = await supabaseAdmin.rpc('register_delivery_identity_document', { p_user: (req as any).user.id, p_path: path });
  if (registered.error) {
    await supabaseAdmin.storage.from('delivery-partner-documents').remove([path]);
    throw new ApiError('Unable to attach document to application', 409);
  }
  res.json(apiSuccess(registered.data));
}));
router.get('/admin/applications/:id/documents', asyncHandler(async (req, res) => {
  if (!(req as any).isAdmin) throw new ApiError('Super admin access required', 403);
  const id = z.string().uuid().parse(req.params.id);
  const docs = await supabaseAdmin.from('delivery_partner_documents').select('id,document_type,storage_path,created_at').eq('partner_id',id).eq('document_type','identity').order('created_at',{ascending:false}).limit(10);
  if (docs.error) throw new ApiError('Unable to load documents',503);
  const result = [];
  for (const doc of docs.data || []) {
    const signed = await supabaseAdmin.storage.from('delivery-partner-documents').createSignedUrl(doc.storage_path, 60);
    if (signed.error || !signed.data) throw new ApiError('Unable to open document',503);
    result.push({id:doc.id, document_type:doc.document_type, created_at:doc.created_at, url:signed.data.signedUrl});
  }
  res.json(apiSuccess(result));
}));
export default router;
