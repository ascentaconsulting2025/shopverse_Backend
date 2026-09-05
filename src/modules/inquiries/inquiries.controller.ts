import { asyncHandler } from '../../utils/asyncHandler';
import { ApiError } from '../../utils/apiError';
import { apiSuccess } from '../../utils/apiResponse';
import { supabaseAdmin } from '../../config/supabaseClient';

export const createInquiry = asyncHandler(async (req, res) => {
  const { customer_name, customer_phone, message } = req.body;
  if (!customer_name || !customer_phone) throw new ApiError('Customer name and phone are required', 400);
  const { data: business } = await supabaseAdmin.from('businesses').select('id').eq('id', req.params.businessId).eq('is_published', true).single();
  if (!business) throw new ApiError('Business not found', 404);
  const { data, error } = await supabaseAdmin.from('inquiries').insert({ business_id: business.id, customer_name, customer_phone, message: message || null }).select().single();
  if (error) throw new ApiError(error.message, 400);
  res.status(201).json(apiSuccess(data));
});
