import { isAdminUser } from '../../middlewares/authGuard';
import { Request, Response, NextFunction } from 'express';
import { issueSession, readRefresh, clearRefresh, sessionId } from './session';
import { supabaseAdmin, createAuthClient } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { asyncHandler } from '../../utils/asyncHandler';
import { apiSuccess } from '../../utils/apiResponse';
import { adminCreateUserSchema, loginSchema, registerSchema } from './auth.schema';

export const register = asyncHandler(async (req, res) => {
  const input = registerSchema.parse(req.body);
  if (isAdminUser({email:input.email})) throw new ApiError('This email is reserved for administrator provisioning',403);
  const { data, error } = await supabaseAdmin.auth.admin.createUser({
    email: input.email, password: input.password, email_confirm: true,
    user_metadata: { full_name: input.full_name || '' },
  });
  if (error || !data.user) throw new ApiError(error?.message || 'Could not create account', 400);
  const { error: profileError } = await supabaseAdmin.from('profiles').upsert({ id: data.user.id, full_name: input.full_name || null });
  if (profileError) throw new ApiError(profileError.message, 500);
  const session = await createAuthClient().auth.signInWithPassword({ email: input.email, password: input.password });
  if (session.error) throw new ApiError(session.error.message, 500);
  res.status(201).json(apiSuccess(await issueSession(res, session.data.session, data.user, true)));
});

export const login = asyncHandler(async (req, res) => {
  const input = loginSchema.parse(req.body);
  const { data, error } = await createAuthClient().auth.signInWithPassword(input);
  if (error || !data.session) throw new ApiError(error?.message || 'Invalid email or password', 401);
  res.json(apiSuccess(await issueSession(res, data.session, data.user, true)));
});

export const createUser = asyncHandler(async (req, res) => {
  if (!(req as any).isAdmin) throw new ApiError('Administrator access required', 403);
  const input = adminCreateUserSchema.parse(req.body);
  if (isAdminUser({email:input.email})) throw new ApiError('Provision Super Admin accounts through the identity provider',403);
  const { data, error } = await supabaseAdmin.auth.admin.createUser({
    email: input.email,
    password: input.password,
    email_confirm: true,
    user_metadata: { full_name: input.full_name },
    app_metadata: { created_by: (req as any).user.id, creation_method: 'administrator' },
  });
  if (error || !data.user) throw new ApiError(error?.message || 'Could not create account', 400);
  const { error: profileError } = await supabaseAdmin.from('profiles').upsert({
    id: data.user.id,
    full_name: input.full_name,
  });
  if (profileError) {
    await supabaseAdmin.auth.admin.deleteUser(data.user.id);
    throw new ApiError(profileError.message, 500);
  }
  res.status(201).json(apiSuccess({
    user: { id: data.user.id, email: data.user.email, full_name: input.full_name, created_at: data.user.created_at },
  }));
});

// Coalesce rotation for requests using the same cookie in this process.
const refreshes = new Map<string, Promise<any>>();
async function refreshData(token: string) {
  if (!token) throw new ApiError('No saved session', 401);
  let pending = refreshes.get(token);
  if (!pending) {
    pending = createAuthClient().auth.refreshSession({ refresh_token: token });
    refreshes.set(token, pending);
    void pending.finally(() => { setTimeout(() => refreshes.delete(token), 1000).unref(); }).catch(() => {});
  }
  const result = await pending;
  if (result.error || !result.data.session) {
    const status = result.error?.status;
    throw new ApiError('Session could not be restored', !status || status >= 500 ? 503 : 401);
  }
  return result.data;
}
export const refresh = asyncHandler(async (req, res) => {
  try {
    const data = await refreshData(readRefresh(req));
    res.json(apiSuccess(await issueSession(res, data.session, data.user)));
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) clearRefresh(res);
    throw error;
  }
});
export const logout = asyncHandler(async (req, res) => {
  const token = readRefresh(req);
  const bearer = /^Bearer ([^\s]+)$/i.exec(req.headers.authorization || '')?.[1];
  if (bearer) {
    const { data, error } = await supabaseAdmin.auth.getUser(bearer);
    if (!error && data.user) {
      const revoked = await supabaseAdmin.from('auth_sessions').update({ revoked_at: new Date().toISOString() }).eq('id', sessionId(bearer)).eq('user_id', data.user.id);
      if (revoked.error) throw new ApiError('Could not revoke session', 503);
      const provider = await supabaseAdmin.auth.admin.signOut(bearer, 'local');
      if (provider.error && ![401, 403, 404].includes(provider.error.status || 0)) throw new ApiError('Could not revoke provider session', 503);
      clearRefresh(res);
      res.json(apiSuccess({ message: 'Signed out' }));
      return;
    }
  }
  if (token) {
    try {
      const data = await refreshData(token);
      const { error } = await supabaseAdmin.from('auth_sessions').update({ revoked_at: new Date().toISOString() }).eq('id', sessionId(data.session.access_token));
      if (error) throw new ApiError('Could not revoke session', 503);
      const signedOut = await supabaseAdmin.auth.admin.signOut(data.session.access_token, 'local');
      if (signedOut.error && signedOut.error.status !== 404) throw new ApiError('Could not revoke provider session', 503);
    } catch (error) {
      if (!(error instanceof ApiError) || error.status !== 401) throw error;
    }
  }
  clearRefresh(res);
  res.json(apiSuccess({ message: 'Signed out' }));
});
