"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_routes_1 = __importDefault(require("../modules/auth/auth.routes"));
const business_routes_1 = __importDefault(require("../modules/business/business.routes"));
const products_routes_1 = __importDefault(require("../modules/products/products.routes"));
const inquiries_routes_1 = __importDefault(require("../modules/inquiries/inquiries.routes"));
const router = (0, express_1.Router)();
router.use('/auth', auth_routes_1.default);
router.use('/businesses', business_routes_1.default);
router.use('/businesses', products_routes_1.default);
router.use('/businesses', inquiries_routes_1.default);
exports.default = router;
