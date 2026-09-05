"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.logout = exports.login = exports.register = void 0;
const supabaseClient_1 = require("../../config/supabaseClient");
const apiError_1 = require("../../utils/apiError");
const asyncHandler_1 = require("../../utils/asyncHandler");
const apiResponse_1 = require("../../utils/apiResponse");
const auth_schema_1 = require("./auth.schema");
exports.register = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const input = auth_schema_1.registerSchema.parse(req.body);
    const { data, error } = await supabaseClient_1.supabaseAdmin.auth.admin.createUser({
        email: input.email, password: input.password, email_confirm: true,
        user_metadata: { full_name: input.full_name || '' },
    });
    if (error || !data.user)
        throw new apiError_1.ApiError(error?.message || 'Could not create account', 400);
    const { error: profileError } = await supabaseClient_1.supabaseAdmin.from('profiles').upsert({ id: data.user.id, full_name: input.full_name || null });
    if (profileError)
        throw new apiError_1.ApiError(profileError.message, 500);
    const session = await supabaseClient_1.supabaseAdmin.auth.signInWithPassword({ email: input.email, password: input.password });
    if (session.error)
        throw new apiError_1.ApiError(session.error.message, 500);
    res.status(201).json((0, apiResponse_1.apiSuccess)({ user: data.user, role: 'user', session: session.data.session }));
});
exports.login = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const input = auth_schema_1.loginSchema.parse(req.body);
    const { data, error } = await supabaseClient_1.supabaseAdmin.auth.signInWithPassword(input);
    if (error || !data.session)
        throw new apiError_1.ApiError(error?.message || 'Invalid email or password', 401);
    const adminEmails = (process.env.ADMIN_EMAILS || '').split(',').map(email => email.trim().toLowerCase()).filter(Boolean);
    res.json((0, apiResponse_1.apiSuccess)({ user: data.user, role: adminEmails.includes(data.user.email?.toLowerCase() || '') ? 'admin' : 'user', session: data.session }));
});
exports.logout = (0, asyncHandler_1.asyncHandler)(async (_req, res) => res.json((0, apiResponse_1.apiSuccess)({ message: 'Signed out. Discard the client access token.' })));
