import { Request, Response, NextFunction } from 'express';

export const createProduct = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'create product stub' } });
};

export const listProducts = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'list products stub' } });
};

export const updateProduct = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'update product stub' } });
};

export const deleteProduct = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'delete product stub' } });
};
