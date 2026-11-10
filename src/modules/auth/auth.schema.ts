import { z } from 'zod';

export const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
  full_name: z.string().optional(),
});

export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
});

export const adminCreateUserSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  full_name: z.string().trim().min(1).max(120),
});

export const verifyEmailSchema = z.object({ email: z.string().trim().email().max(254), otp: z.string().regex(/^\d{6,8}$/), password: z.string().min(6) });
