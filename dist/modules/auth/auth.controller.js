"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.logout = exports.refresh = exports.createUser = exports.login = exports.register = void 0;
const authGuard_1 = require("../../middlewares/authGuard");
const session_1 = require("./session");
const supabaseClient_1 = require("../../config/supabaseClient");
const apiError_1 = require("../../utils/apiError");
const asyncHandler_1 = require("../../utils/asyncHandler");
const apiResponse_1 = require("../../utils/apiResponse");
const auth_schema_1 = require("./auth.schema");
exports.register = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const input = auth_schema_1.registerSchema.parse(req.body);
    if ((0, authGuard_1.isAdminUser)({ email: input.email }))
        throw new apiError_1.ApiError('This email is reserved for administrator provisioning', 403);
    const { data, error } = await supabaseClient_1.supabaseAdmin.auth.admin.createUser({
        email: input.email, password: input.password, email_confirm: true,
        user_metadata: { full_name: input.full_name || '' },
    });
    if (error || !data.user)
        throw new apiError_1.ApiError(error?.message || 'Could not create account', 400);
    const { error: profileError } = await supabaseClient_1.supabaseAdmin.from('profiles').upsert({ id: data.user.id, full_name: input.full_name || null });
    if (profileError)
        throw new apiError_1.ApiError(profileError.message, 500);
    const session = await (0, supabaseClient_1.createAuthClient)().auth.signInWithPassword({ email: input.email, password: input.password });
    if (session.error)
        throw new apiError_1.ApiError(session.error.message, 500);
    res.status(201).json((0, apiResponse_1.apiSuccess)(await (0, session_1.issueSession)(res, session.data.session, data.user, true)));
});
exports.login = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const input = auth_schema_1.loginSchema.parse(req.body);
    const { data, error } = await (0, supabaseClient_1.createAuthClient)().auth.signInWithPassword(input);
    if (error || !data.session)
        throw new apiError_1.ApiError(error?.message || 'Invalid email or password', 401);
    res.json((0, apiResponse_1.apiSuccess)(await (0, session_1.issueSession)(res, data.session, data.user, true)));
});
exports.createUser = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    if (!req.isAdmin)
        throw new apiError_1.ApiError('Administrator access required', 403);
    const input = auth_schema_1.adminCreateUserSchema.parse(req.body);
    if ((0, authGuard_1.isAdminUser)({ email: input.email }))
        throw new apiError_1.ApiError('Provision Super Admin accounts through the identity provider', 403);
    const { data, error } = await supabaseClient_1.supabaseAdmin.auth.admin.createUser({
        email: input.email,
        password: input.password,
        email_confirm: true,
        user_metadata: { full_name: input.full_name },
        app_metadata: { created_by: req.user.id, creation_method: 'administrator' },
    });
    if (error || !data.user)
        throw new apiError_1.ApiError(error?.message || 'Could not create account', 400);
    const { error: profileError } = await supabaseClient_1.supabaseAdmin.from('profiles').upsert({
        id: data.user.id,
        full_name: input.full_name,
    });
    if (profileError) {
        await supabaseClient_1.supabaseAdmin.auth.admin.deleteUser(data.user.id);
        throw new apiError_1.ApiError(profileError.message, 500);
    }
    res.status(201).json((0, apiResponse_1.apiSuccess)({
        user: { id: data.user.id, email: data.user.email, full_name: input.full_name, created_at: data.user.created_at },
    }));
});
// Coalesce rotation for requests using the same cookie in this process.
const refreshes = new Map();
async function refreshData(token) {
    if (!token)
        throw new apiError_1.ApiError('No saved session', 401);
    let pending = refreshes.get(token);
    if (!pending) {
        pending = (0, supabaseClient_1.createAuthClient)().auth.refreshSession({ refresh_token: token });
        refreshes.set(token, pending);
        void pending.finally(() => { setTimeout(() => refreshes.delete(token), 1000).unref(); }).catch(() => { });
    }
    const result = await pending;
    if (result.error || !result.data.session) {
        const status = result.error?.status;
        throw new apiError_1.ApiError('Session could not be restored', !status || status >= 500 ? 503 : 401);
    }
    return result.data;
}
exports.refresh = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    try {
        const data = await refreshData((0, session_1.readRefresh)(req));
        res.json((0, apiResponse_1.apiSuccess)(await (0, session_1.issueSession)(res, data.session, data.user)));
    }
    catch (error) {
        if (error instanceof apiError_1.ApiError && error.status === 401)
            (0, session_1.clearRefresh)(res);
        throw error;
    }
});
exports.logout = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const token = (0, session_1.readRefresh)(req);
    const bearer = /^Bearer ([^\s]+)$/i.exec(req.headers.authorization || '')?.[1];
    if (bearer) {
        const { data, error } = await supabaseClient_1.supabaseAdmin.auth.getUser(bearer);
        if (!error && data.user) {
            const revoked = await supabaseClient_1.supabaseAdmin.from('auth_sessions').update({ revoked_at: new Date().toISOString() }).eq('id', (0, session_1.sessionId)(bearer)).eq('user_id', data.user.id);
            if (revoked.error)
                throw new apiError_1.ApiError('Could not revoke session', 503);
            const provider = await supabaseClient_1.supabaseAdmin.auth.admin.signOut(bearer, 'local');
            if (provider.error && ![401, 403, 404].includes(provider.error.status || 0))
                throw new apiError_1.ApiError('Could not revoke provider session', 503);
            (0, session_1.clearRefresh)(res);
            res.json((0, apiResponse_1.apiSuccess)({ message: 'Signed out' }));
            return;
        }
    }
    if (token) {
        try {
            const data = await refreshData(token);
            const { error } = await supabaseClient_1.supabaseAdmin.from('auth_sessions').update({ revoked_at: new Date().toISOString() }).eq('id', (0, session_1.sessionId)(data.session.access_token));
            if (error)
                throw new apiError_1.ApiError('Could not revoke session', 503);
            const signedOut = await supabaseClient_1.supabaseAdmin.auth.admin.signOut(data.session.access_token, 'local');
            if (signedOut.error && signedOut.error.status !== 404)
                throw new apiError_1.ApiError('Could not revoke provider session', 503);
        }
        catch (error) {
            if (!(error instanceof apiError_1.ApiError) || error.status !== 401)
                throw error;
        }
    }
    (0, session_1.clearRefresh)(res);
    res.json((0, apiResponse_1.apiSuccess)({ message: 'Signed out' }));
});
