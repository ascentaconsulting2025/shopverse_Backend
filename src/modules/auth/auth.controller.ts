import { Request, Response, NextFunction } from 'express';

export const register = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'register stub' } });
};

export const login = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'login stub' } });
};

export const logout = async (req: Request, res: Response, next: NextFunction) => {
  res.json({ success: true, data: { message: 'logout stub' } });
};
