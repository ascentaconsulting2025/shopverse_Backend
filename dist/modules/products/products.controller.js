"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteProduct = exports.updateProduct = exports.getProduct = exports.listProducts = exports.createProduct = void 0;
const asyncHandler_1 = require("../../utils/asyncHandler");
const apiError_1 = require("../../utils/apiError");
const apiResponse_1 = require("../../utils/apiResponse");
const supabaseClient_1 = require("../../config/supabaseClient");
const products_service_1 = require("./products.service");
const cloudinaryAsset_1 = require("../../utils/cloudinaryAsset");
const requireBusinessOwner = async (businessId, userId, isAdmin = false) => {
    const { data } = await supabaseClient_1.supabaseAdmin.from('businesses').select('id, owner_id').eq('id', businessId).single();
    if (!data)
        throw new apiError_1.ApiError('Business not found', 404);
    if (data.owner_id !== userId && !isAdmin)
        throw new apiError_1.ApiError('You do not own this business', 403);
};
const toProduct = (row) => ({
    id: row.id,
    name: { en: row.name_en ?? row.name ?? '', mr: row.name_mr ?? row.name ?? '' },
    description: { en: row.description_en ?? row.description ?? '', mr: row.description_mr ?? row.description ?? '' },
    price: row.price == null || Number(row.price) <= 0 ? undefined : Number(row.price), originalPrice: row.original_price == null || Number(row.original_price) <= 0 ? undefined : Number(row.original_price),
    image: row.image_url || '', imagePublicId: row.image_public_id || '', category: { en: row.category_en ?? row.category ?? '', mr: row.category_mr ?? row.category ?? '' },
    isAvailable: row.is_available ?? true, createdAt: row.created_at, updatedAt: row.updated_at,
});
exports.createProduct = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    await requireBusinessOwner(req.params.businessId, req.user.id, req.isAdmin);
    res.status(201).json((0, apiResponse_1.apiSuccess)(toProduct(await products_service_1.productsService.create(req.params.businessId, req.body))));
});
exports.listProducts = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    res.json((0, apiResponse_1.apiSuccess)((await products_service_1.productsService.list(req.params.businessId)).map(toProduct)));
});
exports.getProduct = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    res.json((0, apiResponse_1.apiSuccess)(toProduct(await (0, products_service_1.requireProduct)(req.params.id))));
});
exports.updateProduct = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const existing = await (0, products_service_1.requireProduct)(req.params.id);
    await requireBusinessOwner(existing.business_id, req.user.id, req.isAdmin);
    if (req.body.image !== undefined) {
        const nextPublicId = req.body.imagePublicId || (0, cloudinaryAsset_1.cloudinaryPublicIdFromUrl)(req.body.image);
        if (existing.image_public_id && existing.image_public_id !== nextPublicId) {
            await (0, cloudinaryAsset_1.deleteCloudinaryImage)(existing.image_public_id, existing.id);
        }
    }
    res.json((0, apiResponse_1.apiSuccess)(toProduct(await products_service_1.productsService.update(req.params.id, req.body))));
});
exports.deleteProduct = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const existing = await (0, products_service_1.requireProduct)(req.params.id);
    await requireBusinessOwner(existing.business_id, req.user.id, req.isAdmin);
    await (0, cloudinaryAsset_1.deleteCloudinaryImage)(existing.image_public_id, existing.id);
    await products_service_1.productsService.remove(req.params.id);
    res.status(204).send();
});
