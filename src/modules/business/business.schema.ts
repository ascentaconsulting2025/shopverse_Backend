import { z } from 'zod';

export const createBusinessSchema = z.object({
  business_name: z.string().min(1),
  category: z.string().optional(),
  description: z.string().optional(),
  whatsapp_number: z.string().optional(),
  address: z.string().optional(),
});
