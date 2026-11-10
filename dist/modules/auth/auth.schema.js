"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.verifyEmailSchema = exports.adminCreateUserSchema = exports.loginSchema = exports.registerSchema = void 0;
const zod_1 = require("zod");
exports.registerSchema = zod_1.z.object({
    email: zod_1.z.string().email(),
    password: zod_1.z.string().min(6),
    full_name: zod_1.z.string().optional(),
});
exports.loginSchema = zod_1.z.object({
    email: zod_1.z.string().email(),
    password: zod_1.z.string().min(6),
});
exports.adminCreateUserSchema = zod_1.z.object({
    email: zod_1.z.string().email(),
    password: zod_1.z.string().min(8),
    full_name: zod_1.z.string().trim().min(1).max(120),
});
exports.verifyEmailSchema = zod_1.z.object({ email: zod_1.z.string().trim().email().max(254), otp: zod_1.z.string().regex(/^\d{6,8}$/), password: zod_1.z.string().min(6) });
