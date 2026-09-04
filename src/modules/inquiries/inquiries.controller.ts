import { Request, Response, NextFunction } from 'express';

export const createInquiry = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'create inquiry stub' } });
};
