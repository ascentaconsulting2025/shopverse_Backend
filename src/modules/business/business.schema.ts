import { z } from 'zod';

export const sectionVisibilitySchema = z.object({
  products: z.boolean(),
  services: z.boolean(),
  special_offers: z.boolean(),
  photo_gallery: z.boolean(),
  upcoming_events: z.boolean(),
}).strict();

export const createBusinessSchema = z.object({
  business_name: z.string().min(1),
  category: z.string().optional(),
  description: z.string().optional(),
  whatsapp_number: z.string().optional(),
  address: z.string().optional(),
});
