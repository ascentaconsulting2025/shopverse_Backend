"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.manageProducts = exports.deleteProduct = exports.updateProduct = exports.getProduct = exports.listProducts = exports.createProduct = void 0;
const packages_service_1 = require("../packages/packages.service");
const categories_service_1 = require("../categories/categories.service");
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
    images: row.images || [], specifications: row.specifications || {},
    id: row.id, categoryId: row.folder_category_id ?? null, isPublished: row.is_published !== false,
    name: { en: row.name_en ?? row.name ?? '', mr: row.name_mr ?? row.name ?? '' },
    description: { en: row.description_en ?? row.description ?? '', mr: row.description_mr ?? row.description ?? '' },
    price: row.price == null || Number(row.price) <= 0 ? undefined : Number(row.price), originalPrice: row.original_price == null || Number(row.original_price) <= 0 ? undefined : Number(row.original_price),
    image: row.image_url || '', imagePublicId: row.image_public_id || '', category: { en: row.category_en ?? row.category ?? '', mr: row.category_mr ?? row.category ?? '' },
    isAvailable: row.is_available ?? true, createdAt: row.created_at, updatedAt: row.updated_at,
});
exports.createProduct = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    await requireBusinessOwner(req.params.businessId, req.user.id, req.isAdmin);
    await (0, packages_service_1.requirePackageFeature)(req.params.businessId, 'products', true);
    res.status(201).json((0, apiResponse_1.apiSuccess)(toProduct(await products_service_1.productsService.create(req.params.businessId, req.body))));
});
exports.listProducts = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const rows = await products_service_1.productsService.list(req.params.businessId);
    res.json((0, apiResponse_1.apiSuccess)((await (0, categories_service_1.publicItems)(req.params.businessId, 'product', rows)).map(toProduct)));
});
exports.getProduct = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const item = await (0, products_service_1.requireProduct)(req.params.id);
    if (!(await (0, categories_service_1.publicItems)(item.business_id, 'product', [item])).length)
        throw new apiError_1.ApiError('Item not found', 404);
    res.json((0, apiResponse_1.apiSuccess)(toProduct(item)));
});
exports.updateProduct = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const existing = await (0, products_service_1.requireProduct)(req.params.id);
    await requireBusinessOwner(existing.business_id, req.user.id, req.isAdmin);
    if (req.body.isPublished === true && existing.is_published === false)
        await (0, packages_service_1.requirePackageFeature)(existing.business_id, 'products');
    await (0, categories_service_1.validateCategory)(existing.business_id, 'product', req.body.categoryId);
    const saved = await products_service_1.productsService.update(req.params.id, req.body);
    if (req.body.image !== undefined) {
        const nextPublicId = req.body.imagePublicId || (0, cloudinaryAsset_1.cloudinaryPublicIdFromUrl)(req.body.image);
        if (existing.image_public_id && existing.image_public_id !== nextPublicId) {
            // Preserve the successful save even if non-critical cleanup is unavailable.
            void (0, cloudinaryAsset_1.deleteUnreferencedCloudinaryImage)(existing.image_public_id, existing.id).catch(error => console.error('Replacement cleanup failed', error));
        }
    }
    res.json((0, apiResponse_1.apiSuccess)(toProduct(saved)));
});
exports.deleteProduct = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const existing = await (0, products_service_1.requireProduct)(req.params.id);
    await requireBusinessOwner(existing.business_id, req.user.id, req.isAdmin);
    await (0, cloudinaryAsset_1.deleteCloudinaryImage)(existing.image_public_id, existing.id);
    await products_service_1.productsService.remove(req.params.id);
    res.status(204).send();
});
exports.manageProducts = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    await (0, categories_service_1.requireCategoryOwner)(req.params.businessId, req);
    res.json((0, apiResponse_1.apiSuccess)((await products_service_1.productsService.list(req.params.businessId)).map(toProduct)));
});
