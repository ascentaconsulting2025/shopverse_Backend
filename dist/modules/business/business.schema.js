"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.businessPayloadSchema = exports.createBusinessSchema = exports.sectionVisibilitySchema = void 0;
const zod_1 = require("zod");
exports.sectionVisibilitySchema = zod_1.z.object({
    products: zod_1.z.boolean(),
    services: zod_1.z.boolean(),
    special_offers: zod_1.z.boolean(),
    photo_gallery: zod_1.z.boolean(),
    upcoming_events: zod_1.z.boolean(),
}).strict();
exports.createBusinessSchema = zod_1.z.object({
    business_name: zod_1.z.string().min(1),
    category: zod_1.z.string().optional(),
    description: zod_1.z.string().optional(),
    whatsapp_number: zod_1.z.string().optional(),
    address: zod_1.z.string().optional(),
});
const optionalMarathiText = zod_1.z.string().trim().max(5000).nullable().optional();
const bilingualText = zod_1.z.object({
    en: zod_1.z.string().trim().max(5000).optional(),
    mr: zod_1.z.string().trim().max(5000).optional(),
});
exports.businessPayloadSchema = zod_1.z.object({
    businessName: zod_1.z.union([
        zod_1.z.string().trim().min(1),
        bilingualText,
    ]).optional(),
    category: zod_1.z.union([zod_1.z.string().trim().max(5000), bilingualText]).optional(),
    ownerName: zod_1.z.union([zod_1.z.string().trim().max(5000), bilingualText]).optional(),
    designation: zod_1.z.union([zod_1.z.string().trim().max(5000), bilingualText]).optional(),
    tagline: zod_1.z.union([zod_1.z.string().trim().max(5000), bilingualText]).optional(),
    about: zod_1.z.union([zod_1.z.string().trim().max(5000), bilingualText]).optional(),
    businessNameMr: optionalMarathiText,
    categoryMr: optionalMarathiText,
    ownerNameMr: optionalMarathiText,
    designationMr: optionalMarathiText,
    taglineMr: optionalMarathiText,
    aboutMr: optionalMarathiText,
}).passthrough();
