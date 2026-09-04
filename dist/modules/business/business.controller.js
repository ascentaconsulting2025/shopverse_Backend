"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateBusiness = exports.getBusinessBySlug = exports.createBusiness = void 0;
const createBusiness = async (req, res, next) => {
    res.json({ success: true, data: { message: 'create business stub' } });
};
exports.createBusiness = createBusiness;
const getBusinessBySlug = async (req, res, next) => {
    res.json({ success: true, data: { message: 'get business stub' } });
};
exports.getBusinessBySlug = getBusinessBySlug;
const updateBusiness = async (req, res, next) => {
    res.json({ success: true, data: { message: 'update business stub' } });
};
exports.updateBusiness = updateBusiness;
