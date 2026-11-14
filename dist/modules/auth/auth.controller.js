"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.logout = exports.refresh = exports.createUser = exports.googleLogin = exports.verifyEmail = exports.login = exports.register = void 0;
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
    const { data, error } = await (0, supabaseClient_1.createAuthClient)().auth.signUp({
        email: input.email, password: input.password,
        options: { data: { full_name: input.full_name || '' } },
    });
    if (error)
        throw new apiError_1.ApiError(error.message, 400);
    if (data.session)
        throw new apiError_1.ApiError('Email confirmation must be enabled on the authentication provider', 503);
    res.status(201).json((0, apiResponse_1.apiSuccess)({ message: 'Check your email for a verification code.' }));
});
exports.login = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const input = auth_schema_1.loginSchema.parse(req.body);
    const { data, error } = await (0, supabaseClient_1.createAuthClient)().auth.signInWithPassword({ email: input.email, password: input.password });
    if (error || !data.session)
        throw new apiError_1.ApiError('Invalid email or password', 401);
    if (data.user?.email?.toLowerCase() === 'admin@gmail.com' && (0, authGuard_1.isAdminUser)(data.user)) {
        const { error: profileError } = await supabaseClient_1.supabaseAdmin.from('profiles').upsert({ id: data.user.id, full_name: data.user.user_metadata?.full_name || null }, { onConflict: 'id', ignoreDuplicates: true });
        if (profileError)
            throw new apiError_1.ApiError('Could not create account profile', 500);
        res.json((0, apiResponse_1.apiSuccess)(await (0, session_1.issueSession)(res, data.session, data.user, true)));
        return;
    }
    const sent = await (0, supabaseClient_1.createAuthClient)().auth.signInWithOtp({ email: input.email, options: { shouldCreateUser: false } });
    if (sent.error) {
        console.error('Authentication login: verification code delivery failed');
        throw new apiError_1.ApiError('Could not send verification code. Please try again.', 503);
    }
    res.json((0, apiResponse_1.apiSuccess)({ message: 'Check your email for a verification code.' }));
});
exports.verifyEmail = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const { email, otp, password } = auth_schema_1.verifyEmailSchema.parse(req.body);
    const { data, error } = await (0, supabaseClient_1.createAuthClient)().auth.verifyOtp({ email, token: otp, type: 'email' });
    if (error || !data.session || !data.user)
        throw new apiError_1.ApiError('Invalid or expired verification code', 401);
    const { error: profileError } = await supabaseClient_1.supabaseAdmin.from('profiles').upsert({ id: data.user.id, full_name: data.user.user_metadata?.full_name || null }, { onConflict: 'id', ignoreDuplicates: true });
    if (profileError)
        throw new apiError_1.ApiError('Could not create account profile', 500);
    const passwordCheck = await (0, supabaseClient_1.createAuthClient)().auth.signInWithPassword({ email, password });
    if (passwordCheck.error || !passwordCheck.data.session || !passwordCheck.data.user)
        throw new apiError_1.ApiError('Invalid email or password', 401);
    res.json((0, apiResponse_1.apiSuccess)(await (0, session_1.issueSession)(res, passwordCheck.data.session, passwordCheck.data.user, true)));
});
exports.googleLogin = (0, asyncHandler_1.asyncHandler)(async (req, res) => {
    const { credential, nonce } = req.body || {};
    if (typeof credential !== 'string' || credential.length > 10000 || typeof nonce !== 'string' || !/^[a-f0-9]{64}$/.test(nonce))
        throw new apiError_1.ApiError('Invalid Google credential', 400);
    const { data, error } = await (0, supabaseClient_1.createAuthClient)().auth.signInWithIdToken({ provider: 'google', token: credential, nonce });
    if (error || !data.session || !data.user)
        throw new apiError_1.ApiError(error?.message || 'Google sign in failed', 401);
    const { error: profileError } = await supabaseClient_1.supabaseAdmin.from('profiles').upsert({ id: data.user.id, full_name: data.user.user_metadata?.full_name || null }, { onConflict: 'id', ignoreDuplicates: true });
    if (profileError)
        throw new apiError_1.ApiError('Could not create account profile', 500);
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
