"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteProduct = exports.updateProduct = exports.listProducts = exports.createProduct = void 0;
const createProduct = async (req, res, next) => {
    res.json({ success: true, data: { message: 'create product stub' } });
};
exports.createProduct = createProduct;
const listProducts = async (req, res, next) => {
    res.json({ success: true, data: { message: 'list products stub' } });
};
exports.listProducts = listProducts;
const updateProduct = async (req, res, next) => {
    res.json({ success: true, data: { message: 'update product stub' } });
};
exports.updateProduct = updateProduct;
const deleteProduct = async (req, res, next) => {
    res.json({ success: true, data: { message: 'delete product stub' } });
};
exports.deleteProduct = deleteProduct;
