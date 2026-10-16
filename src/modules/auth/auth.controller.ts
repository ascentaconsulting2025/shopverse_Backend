import { Request, Response, NextFunction } from 'express';
import { supabaseAdmin, createAuthClient } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { asyncHandler } from '../../utils/asyncHandler';
import { apiSuccess } from '../../utils/apiResponse';
import { loginSchema, registerSchema } from './auth.schema';

export const register = asyncHandler(async (req, res) => {
  const input = registerSchema.parse(req.body);
  const { data, error } = await supabaseAdmin.auth.admin.createUser({
    email: input.email, password: input.password, email_confirm: true,
    user_metadata: { full_name: input.full_name || '' },
  });
  if (error || !data.user) throw new ApiError(error?.message || 'Could not create account', 400);
  const { error: profileError } = await supabaseAdmin.from('profiles').upsert({ id: data.user.id, full_name: input.full_name || null });
  if (profileError) throw new ApiError(profileError.message, 500);
  const session = await createAuthClient().auth.signInWithPassword({ email: input.email, password: input.password });
  if (session.error) throw new ApiError(session.error.message, 500);
  res.status(201).json(apiSuccess({ user: data.user, role: 'user', session: session.data.session }));
});

export const login = asyncHandler(async (req, res) => {
  const input = loginSchema.parse(req.body);
  const { data, error } = await createAuthClient().auth.signInWithPassword(input);
  if (error || !data.session) throw new ApiError(error?.message || 'Invalid email or password', 401);
  const adminEmails = (process.env.ADMIN_EMAILS || '').split(',').map(email => email.trim().toLowerCase()).filter(Boolean);
  res.json(apiSuccess({ user: data.user, role: adminEmails.includes(data.user.email?.toLowerCase() || '') ? 'admin' : 'user', session: data.session }));
});

export const logout = asyncHandler(async (_req, res) => res.json(apiSuccess({ message: 'Signed out. Discard the client access token.' })));
