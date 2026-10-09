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
  social_links: z.record(z.string(), z.string().trim().max(2000).optional()).optional(),
});

const optionalMarathiText = z.string().trim().max(5000).nullable().optional();
const socialLinkValueSchema = z.union([
  z.string().trim().max(2000).refine((value) => !value || /^(https?:\/\/|mailto:|www\.)/i.test(value), 'Social link must be a valid URL or mailto link'),
  z.literal(''),
]);

const socialLinksSchema = z.record(z.string(), socialLinkValueSchema.optional()).transform((links) => {
  return Object.fromEntries(
    Object.entries(links)
      .filter(([, value]) => typeof value === 'string' && value.trim().length > 0)
      .map(([key, value]) => [key, String(value).trim()]),
  );
});

const bilingualText = z.object({
  en: z.string().trim().max(5000).optional(),
  mr: z.string().trim().max(5000).optional(),
});
const businessPersonSchema = z.object({
  id: z.string().uuid().optional(),
  fullName: bilingualText.refine((value) => Boolean(value.en?.trim() || value.mr?.trim()), 'A person name is required'),
  designation: bilingualText.optional(),
  description: bilingualText.optional(),
  profileImage: z.string().trim().max(2000).nullable().optional(),
  profileImagePublicId: z.string().trim().max(500).nullable().optional(),
  displayOrder: z.coerce.number().int().min(0).default(0),
  isPrimary: z.boolean().default(false),
  isActive: z.boolean().default(true),
}).strict();

const richTextMark = z.object({
  text: z.string().max(5000),
  bold: z.boolean().optional(),
}).strict();

const unorderedListStyles = z.enum(['disc', 'circle', 'square']);
const orderedListStyles = z.enum(['decimal', 'lower-alpha', 'upper-alpha', 'lower-roman', 'upper-roman']);
const richTextListItem = z.object({
  type: z.literal('list-item'),
  children: z.array(richTextMark).max(5000),
}).strict();
const richTextParagraph = z.object({
  type: z.literal('paragraph'),
  children: z.array(richTextMark).max(5000),
}).strict();
const richTextList = z.union([
  z.object({ type: z.literal('unordered-list'), style: unorderedListStyles, children: z.array(richTextListItem).max(5000) }).strict(),
  z.object({ type: z.literal('ordered-list'), style: orderedListStyles, children: z.array(richTextListItem).max(5000) }).strict(),
]);

const richTextDocument = z.object({
  type: z.literal('doc'),
  children: z.array(z.union([richTextParagraph, richTextList])).max(5000),
}).strict().refine((document) => JSON.stringify(document).length <= 20000, 'About content is too large');

const richTextValue = z.union([z.string().trim().max(5000), richTextDocument]);
const richBilingualText = z.object({
  en: richTextValue,
  mr: richTextValue,
}).strict();

const slugSchema = z.string()
  .trim()
  .min(1, 'Slug is required.')
  .max(48, 'Slug must be 48 characters or fewer.')
  .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/, 'Use only lowercase letters, numbers, and hyphens.');

export const businessPayloadSchema = z.object({
  slug: slugSchema.optional(),
  businessName: z.union([
    z.string().trim().min(1),
    bilingualText,
  ]).optional(),
  category: z.union([z.string().trim().max(5000), bilingualText]).optional(),
  ownerName: z.union([z.string().trim().max(5000), bilingualText]).optional(),
  designation: z.union([z.string().trim().max(5000), bilingualText]).optional(),
  tagline: z.union([z.string().trim().max(5000), bilingualText]).optional(),
  about: z.union([z.string().trim().max(5000), bilingualText, richBilingualText]).optional(),
  socialLinks: socialLinksSchema.optional(),
  businessNameMr: optionalMarathiText,
  categoryMr: optionalMarathiText,
  ownerNameMr: optionalMarathiText,
  designationMr: optionalMarathiText,
  taglineMr: optionalMarathiText,
  aboutMr: optionalMarathiText,
  people: z.array(businessPersonSchema).max(50).optional().superRefine((people, context) => {
    if (!people) return;
    const activePrimary = people.filter((person) => person.isActive && person.isPrimary);
    if (activePrimary.length > 1) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Only one active primary person is allowed' });
    if (people.some((person) => person.isActive) && activePrimary.length !== 1) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Exactly one active primary person is required' });
    const ids = people.map((person) => person.id).filter(Boolean);
    if (new Set(ids).size !== ids.length) context.addIssue({ code: z.ZodIssueCode.custom, message: 'People must not contain duplicate IDs' });
  }),
}).passthrough();
