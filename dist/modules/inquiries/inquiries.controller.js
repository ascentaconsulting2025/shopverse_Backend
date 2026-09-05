"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createInquiry = void 0;
const asyncHandler_1 = require("../../utils/asyncHandler");
const apiError_1 = require("../../utils/apiError");
const apiResponse_1 = require("../../utils/apiResponse");
const supabaseClient_1 = require("../../config/supabaseClient");
exports.createInquiry = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const { customer_name, customer_phone, message } = req.body;
    if (!customer_name || !customer_phone)
        throw new apiError_1.ApiError('Customer name and phone are required', 400);
    const { data: business } = await supabaseClient_1.supabaseAdmin.from('businesses').select('id').eq('id', req.params.businessId).eq('is_published', true).single();
    if (!business)
        throw new apiError_1.ApiError('Business not found', 404);
    const { data, error } = await supabaseClient_1.supabaseAdmin.from('inquiries').insert({ business_id: business.id, customer_name, customer_phone, message: message || null }).select().single();
    if (error)
        throw new apiError_1.ApiError(error.message, 400);
    res.status(201).json((0, apiResponse_1.apiSuccess)(data));
});
