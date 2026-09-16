"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.businessPayloadSchema = exports.createBusinessSchema = exports.sectionVisibilitySchema = void 0;
const zod_1 = require("zod");
exports.sectionVisibilitySchema = zod_1.z.object({
    products: zod_1.z.boolean(),
    services: zod_1.z.boolean(),
    special_offers: zod_1.z.boolean(),
    photo_gallery: zod_1.z.boolean(),
    upcoming_events: zod_1.z.boolean(),
}).strict();
exports.createBusinessSchema = zod_1.z.object({
    business_name: zod_1.z.string().min(1),
    category: zod_1.z.string().optional(),
    description: zod_1.z.string().optional(),
    whatsapp_number: zod_1.z.string().optional(),
    address: zod_1.z.string().optional(),
    social_links: zod_1.z.record(zod_1.z.string(), zod_1.z.string().trim().max(2000).optional()).optional(),
});
const optionalMarathiText = zod_1.z.string().trim().max(5000).nullable().optional();
const socialLinkValueSchema = zod_1.z.union([
    zod_1.z.string().trim().max(2000).refine((value) => !value || /^(https?:\/\/|mailto:|www\.)/i.test(value), 'Social link must be a valid URL or mailto link'),
    zod_1.z.literal(''),
]);
const socialLinksSchema = zod_1.z.record(zod_1.z.string(), socialLinkValueSchema.optional()).transform((links) => {
    return Object.fromEntries(Object.entries(links)
        .filter(([, value]) => typeof value === 'string' && value.trim().length > 0)
        .map(([key, value]) => [key, String(value).trim()]));
});
const bilingualText = zod_1.z.object({
    en: zod_1.z.string().trim().max(5000).optional(),
    mr: zod_1.z.string().trim().max(5000).optional(),
});
const richTextMark = zod_1.z.object({
    text: zod_1.z.string().max(5000),
    bold: zod_1.z.boolean().optional(),
}).strict();
const unorderedListStyles = zod_1.z.enum(['disc', 'circle', 'square']);
const orderedListStyles = zod_1.z.enum(['decimal', 'lower-alpha', 'upper-alpha', 'lower-roman', 'upper-roman']);
const richTextListItem = zod_1.z.object({
    type: zod_1.z.literal('list-item'),
    children: zod_1.z.array(richTextMark).max(5000),
}).strict();
const richTextParagraph = zod_1.z.object({
    type: zod_1.z.literal('paragraph'),
    children: zod_1.z.array(richTextMark).max(5000),
}).strict();
const richTextList = zod_1.z.union([
    zod_1.z.object({ type: zod_1.z.literal('unordered-list'), style: unorderedListStyles, children: zod_1.z.array(richTextListItem).max(5000) }).strict(),
    zod_1.z.object({ type: zod_1.z.literal('ordered-list'), style: orderedListStyles, children: zod_1.z.array(richTextListItem).max(5000) }).strict(),
]);
const richTextDocument = zod_1.z.object({
    type: zod_1.z.literal('doc'),
    children: zod_1.z.array(zod_1.z.union([richTextParagraph, richTextList])).max(5000),
}).strict().refine((document) => JSON.stringify(document).length <= 20000, 'About content is too large');
const richTextValue = zod_1.z.union([zod_1.z.string().trim().max(5000), richTextDocument]);
const richBilingualText = zod_1.z.object({
    en: richTextValue,
    mr: richTextValue,
}).strict();
exports.businessPayloadSchema = zod_1.z.object({
    businessName: zod_1.z.union([
        zod_1.z.string().trim().min(1),
        bilingualText,
    ]).optional(),
    category: zod_1.z.union([zod_1.z.string().trim().max(5000), bilingualText]).optional(),
    ownerName: zod_1.z.union([zod_1.z.string().trim().max(5000), bilingualText]).optional(),
    designation: zod_1.z.union([zod_1.z.string().trim().max(5000), bilingualText]).optional(),
    tagline: zod_1.z.union([zod_1.z.string().trim().max(5000), bilingualText]).optional(),
    about: zod_1.z.union([zod_1.z.string().trim().max(5000), bilingualText, richBilingualText]).optional(),
    socialLinks: socialLinksSchema.optional(),
    businessNameMr: optionalMarathiText,
    categoryMr: optionalMarathiText,
    ownerNameMr: optionalMarathiText,
    designationMr: optionalMarathiText,
    taglineMr: optionalMarathiText,
    aboutMr: optionalMarathiText,
}).passthrough();
