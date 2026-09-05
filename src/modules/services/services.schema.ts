import { z } from 'zod';

const bilingualField = z.object({
  en: z.string().trim(),
  mr: z.string().trim(),
});

export const createServiceSchema = z.object({
  name: bilingualField.refine(value => value.en.length > 0 && value.mr.length > 0, 'English and Marathi service names are required'),
  startingPrice: z.coerce.number().finite().min(0),
  duration: bilingualField.optional().default({ en: '', mr: '' }),
  category: bilingualField.optional().default({ en: '', mr: '' }),
  description: bilingualField.optional().default({ en: '', mr: '' }),
  image: z.string().trim().optional().default(''),
});

export const updateServiceSchema = createServiceSchema.partial();
