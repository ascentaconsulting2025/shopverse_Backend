import { Request, Response, NextFunction } from 'express';
import { supabaseAdmin } from '../config/supabaseClient';

export function isAdminUser(user: { email?: string | null }) {
  const adminEmails = (process.env.ADMIN_EMAILS || '')
    .split(',').map(email => email.trim().toLowerCase()).filter(Boolean);
  return !!user.email && adminEmails.includes(user.email.toLowerCase());
}

export async function authGuard(req: Request, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, error: { message: 'Missing auth token' } });
  const token = authHeader.replace('Bearer ', '');
  const { data, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !data.user) return res.status(401).json({ success: false, error: { message: 'Invalid token' } });
  (req as any).user = data.user;
  (req as any).isAdmin = isAdminUser(data.user);
  next();
}
