import { z } from 'zod';

const bilingual = z.object({ en: z.string().trim(), mr: z.string().trim() });
const url = z.string().trim().url().optional().or(z.literal(''));
export const eventSchema = z.object({ title: bilingual.refine(v => v.en.length > 0 || v.mr.length > 0, 'Event name is required'), description: bilingual.default({ en: '', mr: '' }), date: z.string().trim().min(1), time: z.string().trim().min(1), venue: bilingual.refine(v => v.en.length > 0 || v.mr.length > 0, 'Venue is required'), enquiryNo: z.string().trim().min(1), eventLink: url.default(''), photo: url.default(''), image: url.default(''), imagePublicId: z.string().trim().optional(), isActive: z.boolean().default(true) });
export const offerSchema = z.object({
  title: bilingual.refine(v => v.en.length > 0 || v.mr.length > 0, 'Offer title is required'),
  description: bilingual.default({ en: '', mr: '' }),
  discountBadge: bilingual.default({ en: '', mr: '' }),
  discountPercentage: z.coerce.number().min(0).max(100).optional(),
  couponCode: z.string().trim().optional().default(''),
  validUntil: bilingual.default({ en: '', mr: '' }),
  terms: bilingual.optional(),
  imageUrl: url.default(''),
  imagePublicId: z.string().trim().optional(),
  isActive: z.boolean().default(true),
});
export const gallerySchema = z.object({ url: z.string().trim().url(), imageUrl: z.string().trim().url().optional(), imagePublicId: z.string().trim().optional(), caption: z.union([z.string().trim(), bilingual]).default(''), category: z.union([z.string().trim(), bilingual]).default(''), sortOrder: z.coerce.number().int().min(0).default(0), isActive: z.boolean().default(true) });
