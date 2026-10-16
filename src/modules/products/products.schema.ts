import { z } from 'zod';

const bilingualField = z.object({ en: z.string(), mr: z.string() });

export const createProductSchema = z.object({
  categoryId: z.string().uuid().nullable().optional(),
  isPublished: z.boolean().optional(),
  name: bilingualField,
  description: bilingualField,
  price: z.union([z.coerce.number().finite().positive(), z.null()]).optional(),
  originalPrice: z.coerce.number().finite().min(0).optional(),
  image: z.string().trim().optional().default(''),
  imagePublicId: z.string().trim().optional(),
  category: bilingualField.optional(),
  isAvailable: z.boolean(),
  sortOrder: z.number().int().optional(),
});

export const updateProductSchema = createProductSchema.extend({
  price: z.union([z.coerce.number().finite().positive(), z.null()]).optional(),
  originalPrice: z.union([z.coerce.number().finite().min(0), z.null()]).optional(),
}).partial();
