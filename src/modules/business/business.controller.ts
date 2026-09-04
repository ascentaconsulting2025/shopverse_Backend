import { Request, Response, NextFunction } from 'express';

export const createBusiness = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'create business stub' } });
};

export const getBusinessBySlug = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'get business stub' } });
};

export const updateBusiness = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'update business stub' } });
};
