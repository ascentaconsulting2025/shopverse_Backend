import { ZodError } from 'zod';
import { Request, Response, NextFunction } from 'express';

export function errorHandler(err: any, req: Request, res: Response, next: NextFunction) {
  // Never log provider objects or request bodies, which may contain credentials.
  console.error('Request failed', { status: err.status || 500, type: err.name || 'Error' });
  const packageStatus = /requires (?:Premium|Standard or Premium)/.test(err.message || '') ? 403 : /limit reached \(maximum \d+\)/.test(err.message || '') ? 409 : null;
  const status = packageStatus ?? (err instanceof ZodError ? 400 : err.code === 'LIMIT_FILE_SIZE' ? 413 : (err.status || 500));
  res.status(status).json({ success: false, error: { message: err instanceof ZodError ? 'Invalid request fields' : status >= 500 ? 'Service temporarily unavailable. Please try again.' : err.message || 'Request failed' } });
}
