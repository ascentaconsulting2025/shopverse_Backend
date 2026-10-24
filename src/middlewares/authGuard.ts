import { Request, Response, NextFunction } from 'express';
import { assertSession } from '../modules/auth/session';
import { supabaseAdmin } from '../config/supabaseClient';

export function isAdminUser(user: { email?: string | null }) {
  const adminEmails = (process.env.ADMIN_EMAILS || '')
    .split(',').map(email => email.trim().toLowerCase()).filter(Boolean);
  return !!user.email && adminEmails.includes(user.email.toLowerCase());
}

export async function authGuard(req: Request, res: Response, next: NextFunction) {
  res.setHeader('Cache-Control', 'private, no-store');
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, error: { message: 'Missing auth token' } });
  const match = /^Bearer ([^\s]+)$/i.exec(authHeader);
  if (!match) return res.status(401).json({ success: false, error: { message: 'Malformed auth token' } });
  const token = match[1];
  try {
  const { data, error } = await supabaseAdmin.auth.getUser(token);
  if (error && (!error.status || error.status >= 500)) return res.status(503).json({ success: false, error: { message: 'Authentication temporarily unavailable' } });
  if (error || !data.user || Date.parse((data.user as any).banned_until || '') > Date.now()) return res.status(401).json({ success: false, error: { message: 'Invalid token' } });
  try { await assertSession(token, data.user.id); } catch (error) { return next(error); }
  (req as any).user = data.user;
  (req as any).isAdmin = isAdminUser(data.user);
  next();
  } catch (error) { next(error); }
}
