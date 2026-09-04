import { Request, Response, NextFunction } from 'express';
import { supabaseAdmin } from '../config/supabaseClient';

export async function authGuard(req: Request, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, error: { message: 'Missing auth token' } });
  const token = authHeader.replace('Bearer ', '');
  const { data, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !data.user) return res.status(401).json({ success: false, error: { message: 'Invalid token' } });
  (req as any).user = data.user;
  next();
}
