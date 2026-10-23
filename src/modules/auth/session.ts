import { Request, Response } from 'express';
import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';

const cookieName = 'shopverse_refresh';
export const sessionDays = Math.max(1, Math.min(90, Number(process.env.SESSION_DAYS) || 30));
const options = () => ({ httpOnly: true, secure: process.env.NODE_ENV === 'production' || process.env.AUTH_COOKIE_SAME_SITE === 'none', sameSite: (process.env.AUTH_COOKIE_SAME_SITE === 'none' ? 'none' : 'lax') as 'none' | 'lax', path: '/api/v1/auth' });
export const readRefresh = (req: Request) => {
  const value = (req.headers.cookie || '').split(';').map(v => v.trim()).find(v => v.startsWith(cookieName + '='));
  try { return value ? decodeURIComponent(value.slice(cookieName.length + 1)) : ''; } catch { return ''; }
};
export const clearRefresh = (res: Response) => res.clearCookie(cookieName, options());
export const sessionId = (jwt: string): string => {
  try { return JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString()).session_id || ''; } catch { return ''; }
};
export async function assertSession(jwt: string, userId: string) {
  const { data, error } = await supabaseAdmin.from('auth_sessions').select('expires_at,revoked_at').eq('id', sessionId(jwt)).eq('user_id', userId).maybeSingle();
  if (error) throw new ApiError('Session validation unavailable', 503);
  if (!data || data.revoked_at || Date.parse(data.expires_at) <= Date.now()) throw new ApiError('Session expired or revoked', 401);
  return data;
}
export async function issueSession(res: Response, session: any, user: any, fresh = false) {
  const id = sessionId(session.access_token);
  if (!id) throw new ApiError('Authentication provider returned an invalid session', 502);
  if (fresh) {
    const { error } = await supabaseAdmin.from('auth_sessions').insert({ id, user_id: user.id, expires_at: new Date(Date.now() + sessionDays * 86400000).toISOString() });
    if (error) throw new ApiError('Could not persist session', 503);
  }
  const active = await assertSession(session.access_token, user.id);
  res.setHeader('Cache-Control', 'no-store');
  res.cookie(cookieName, session.refresh_token, { ...options(), expires: new Date(active.expires_at) });
  const admins = (process.env.ADMIN_EMAILS || '').split(',').map(v => v.trim().toLowerCase());
  return { user, role: admins.includes(user.email?.toLowerCase()) ? 'admin' : 'user', session: { access_token: session.access_token, expires_at: session.expires_at } };
}
