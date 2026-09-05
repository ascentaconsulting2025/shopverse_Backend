"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.productsService = exports.requireProduct = exports.productSelect = void 0;
const supabaseClient_1 = require("../../config/supabaseClient");
const apiError_1 = require("../../utils/apiError");
exports.productSelect = '*';
const requireProduct = async (id) => {
    const { data, error } = await supabaseClient_1.supabaseAdmin.from('products').select(exports.productSelect).eq('id', id).single();
    if (error || !data)
        throw new apiError_1.ApiError('Product not found', 404);
    return data;
};
exports.requireProduct = requireProduct;
exports.productsService = {
    async list(businessId) {
        const { data, error } = await supabaseClient_1.supabaseAdmin.from('products').select(exports.productSelect)
            .eq('business_id', businessId).order('sort_order').order('created_at', { ascending: false });
        if (error)
            throw new apiError_1.ApiError(error.message, 400);
        return data || [];
    },
    async create(businessId, input) {
        const { data, error } = await supabaseClient_1.supabaseAdmin.from('products').insert({
            business_id: businessId,
            name: input.name.en || input.name.mr,
            name_en: input.name.en,
            name_mr: input.name.mr,
            description: input.description.en || input.description.mr || null,
            description_en: input.description.en,
            description_mr: input.description.mr,
            price: input.price,
            original_price: input.originalPrice ?? null,
            image_url: input.image || null,
            category: input.category?.en || input.category?.mr || null,
            category_en: input.category?.en || null,
            category_mr: input.category?.mr || null,
            is_available: input.isAvailable,
            sort_order: input.sortOrder ?? 0,
        }).select(exports.productSelect).single();
        if (error)
            throw new apiError_1.ApiError(error.message, 400);
        return data;
    },
    async update(id, input) {
        const update = { updated_at: new Date().toISOString() };
        if (input.name !== undefined) {
            update.name = input.name.en || input.name.mr;
            update.name_en = input.name.en;
            update.name_mr = input.name.mr;
        }
        if (input.description !== undefined) {
            update.description = input.description.en || input.description.mr || null;
            update.description_en = input.description.en;
            update.description_mr = input.description.mr;
        }
        if (input.price !== undefined)
            update.price = input.price;
        if (input.originalPrice !== undefined)
            update.original_price = input.originalPrice;
        if (input.image !== undefined)
            update.image_url = input.image || null;
        if (input.category !== undefined) {
            update.category = input.category?.en || input.category?.mr || null;
            update.category_en = input.category?.en || null;
            update.category_mr = input.category?.mr || null;
        }
        if (input.isAvailable !== undefined)
            update.is_available = input.isAvailable;
        if (input.sortOrder !== undefined)
            update.sort_order = input.sortOrder;
        const { data, error } = await supabaseClient_1.supabaseAdmin.from('products').update(update).eq('id', id).select(exports.productSelect).single();
        if (error || !data)
            throw new apiError_1.ApiError(error?.message || 'Product not found', error ? 400 : 404);
        return data;
    },
    async remove(id) {
        const { error } = await supabaseClient_1.supabaseAdmin.from('products').delete().eq('id', id);
        if (error)
            throw new apiError_1.ApiError(error.message, 400);
    },
};
