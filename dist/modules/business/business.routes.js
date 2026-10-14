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
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const controller = __importStar(require("./business.controller"));
const authGuard_1 = require("../../middlewares/authGuard");
const validateRequest_1 = require("../../middlewares/validateRequest");
const business_schema_1 = require("./business.schema");
const router = (0, express_1.Router)();
router.get('/mine', authGuard_1.authGuard, controller.listMyBusinesses);
router.get('/count', controller.getBusinessCount);
router.get('/marketplace', controller.listMarketplace);
router.post('/', authGuard_1.authGuard, (0, validateRequest_1.validateRequest)(business_schema_1.businessPayloadSchema), controller.createBusiness);
router.get('/:id/section-visibility', authGuard_1.authGuard, controller.getSectionVisibility);
router.patch('/:id/section-visibility', authGuard_1.authGuard, controller.updateSectionVisibility);
router.get('/:id/usage', authGuard_1.authGuard, controller.getBusinessUsage);
router.get('/:slug', controller.getBusinessBySlug);
router.patch('/:id', authGuard_1.authGuard, (0, validateRequest_1.validateRequest)(business_schema_1.businessPayloadSchema), controller.updateBusiness);
router.delete('/:id', authGuard_1.authGuard, controller.deleteBusiness);
exports.default = router;
