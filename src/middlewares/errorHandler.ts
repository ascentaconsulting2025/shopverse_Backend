import { ZodError } from 'zod';
import { Request, Response, NextFunction } from 'express';

export function errorHandler(err: any, req: Request, res: Response, next: NextFunction) {
  console.error(err);
  const status = err instanceof ZodError ? 400 : err.code === 'LIMIT_FILE_SIZE' ? 413 : (err.status || 500);
  res.status(status).json({ success: false, error: { message: err.message || 'Internal Server Error' } });
}
