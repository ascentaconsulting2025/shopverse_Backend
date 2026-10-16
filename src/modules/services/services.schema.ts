import { z } from 'zod';

const bilingualField = z.object({
  en: z.string().trim(),
  mr: z.string().trim(),
});

export const createServiceSchema = z.object({
  categoryId: z.string().uuid().nullable().optional(),
  isPublished: z.boolean().optional(),
  name: bilingualField.refine(value => value.en.length > 0 && value.mr.length > 0, 'English and Marathi service names are required'),
  startingPrice: z.union([z.coerce.number().finite().positive(), z.null()]).optional(),
  duration: bilingualField.optional().default({ en: '', mr: '' }),
  category: bilingualField.optional().default({ en: '', mr: '' }),
  description: bilingualField.optional().default({ en: '', mr: '' }),
  image: z.string().trim().optional().default(''),
  imagePublicId: z.string().trim().optional(),
});

export const updateServiceSchema = createServiceSchema.partial();
