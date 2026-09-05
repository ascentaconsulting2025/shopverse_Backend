"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createBusinessSchema = exports.sectionVisibilitySchema = void 0;
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
