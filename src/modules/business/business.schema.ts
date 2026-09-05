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

const optionalMarathiText = z.string().trim().max(5000).nullable().optional();
const bilingualText = z.object({
  en: z.string().trim().max(5000).optional(),
  mr: z.string().trim().max(5000).optional(),
});

export const businessPayloadSchema = z.object({
  businessName: z.union([
    z.string().trim().min(1),
    bilingualText,
  ]).optional(),
  category: z.union([z.string().trim().max(5000), bilingualText]).optional(),
  ownerName: z.union([z.string().trim().max(5000), bilingualText]).optional(),
  designation: z.union([z.string().trim().max(5000), bilingualText]).optional(),
  tagline: z.union([z.string().trim().max(5000), bilingualText]).optional(),
  about: z.union([z.string().trim().max(5000), bilingualText]).optional(),
  businessNameMr: optionalMarathiText,
  categoryMr: optionalMarathiText,
  ownerNameMr: optionalMarathiText,
  designationMr: optionalMarathiText,
  taglineMr: optionalMarathiText,
  aboutMr: optionalMarathiText,
}).passthrough();
