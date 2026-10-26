"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const explore_routes_1 = __importDefault(require("../modules/explore/explore.routes"));
const categories_routes_1 = __importStar(require("../modules/categories/categories.routes"));
const express_1 = require("express");
const auth_routes_1 = __importDefault(require("../modules/auth/auth.routes"));
const business_routes_1 = __importDefault(require("../modules/business/business.routes"));
const products_routes_1 = __importDefault(require("../modules/products/products.routes"));
const inquiries_routes_1 = __importDefault(require("../modules/inquiries/inquiries.routes"));
const services_routes_1 = __importDefault(require("../modules/services/services.routes"));
const content_routes_1 = require("../modules/content/content.routes");
const content_schema_1 = require("../modules/content/content.schema");
const uploads_routes_1 = __importDefault(require("../modules/uploads/uploads.routes"));
const router = (0, express_1.Router)();
router.use('/explore', explore_routes_1.default);
router.use('/categories', categories_routes_1.globalCategoryRoutes);
router.use('/auth', auth_routes_1.default);
router.use('/businesses', categories_routes_1.default);
router.use('/businesses', business_routes_1.default);
router.use('/businesses', products_routes_1.default);
router.use('/businesses', inquiries_routes_1.default);
router.use('/businesses', services_routes_1.default);
router.use('/events', (0, content_routes_1.contentRoutes)('events', content_schema_1.eventSchema));
router.use('/offers', (0, content_routes_1.contentRoutes)('offers', content_schema_1.offerSchema));
router.use('/gallery', (0, content_routes_1.contentRoutes)('gallery', content_schema_1.gallerySchema));
router.use('/uploads', uploads_routes_1.default);
exports.default = router;
