"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.productsService = exports.requireProduct = exports.productSelect = void 0;
const categories_service_1 = require("../categories/categories.service");
const supabaseClient_1 = require("../../config/supabaseClient");
const apiError_1 = require("../../utils/apiError");
const cloudinaryAsset_1 = require("../../utils/cloudinaryAsset");
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
        await (0, categories_service_1.validateCategory)(businessId, 'product', input.categoryId);
        const { data, error } = await supabaseClient_1.supabaseAdmin.from('products').insert({
            business_id: businessId,
            ...(input.images !== undefined ? { images: input.images } : {}),
            ...(input.specifications !== undefined ? { specifications: input.specifications } : {}),
            folder_category_id: input.categoryId ?? null,
            is_published: input.isPublished ?? true,
            name: input.name.en || input.name.mr,
            name_en: input.name.en,
            name_mr: input.name.mr,
            description: input.description.en || input.description.mr || null,
            description_en: input.description.en,
            description_mr: input.description.mr,
            price: input.price,
            original_price: input.originalPrice ?? null,
            image_url: input.image || null,
            image_public_id: input.imagePublicId || (0, cloudinaryAsset_1.cloudinaryPublicIdFromUrl)(input.image) || null,
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
        const current = await (0, exports.requireProduct)(id);
        await (0, categories_service_1.validateCategory)(current.business_id, 'product', input.categoryId);
        const update = { updated_at: new Date().toISOString() };
        if (input.images !== undefined)
            update.images = input.images;
        if (input.specifications !== undefined)
            update.specifications = input.specifications;
        if (input.categoryId !== undefined)
            update.folder_category_id = input.categoryId;
        if (input.isPublished !== undefined)
            update.is_published = input.isPublished;
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
        if (input.image !== undefined) {
            update.image_url = input.image || null;
            update.image_public_id = input.imagePublicId || (0, cloudinaryAsset_1.cloudinaryPublicIdFromUrl)(input.image) || null;
        }
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
