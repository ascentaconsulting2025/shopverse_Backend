import { z } from 'zod';

const bilingualField = z.object({ en: z.string(), mr: z.string() });

export const createProductSchema = z.object({
  name: bilingualField,
  description: bilingualField,
  price: z.coerce.number().finite().min(0),
  originalPrice: z.coerce.number().finite().min(0).optional(),
  image: z.string().trim().optional().default(''),
  category: bilingualField.optional(),
  isAvailable: z.boolean(),
  sortOrder: z.number().int().optional(),
});

export const updateProductSchema = createProductSchema.extend({
  originalPrice: z.union([z.coerce.number().finite().min(0), z.null()]).optional(),
}).partial();