
import { cloudinaryPublicIdFromUrl } from '../../utils/cloudinaryAsset';

const baseStats = { totalViews: 0, uniqueVisitors: 0, whatsappClicks: 0, callClicks: 0, websiteClicks: 0, enquiriesCount: 0, qrScans: 0, directionClicks: 0, vcardDownloads: 0 };

function bilingualValue(value: any, fallback = '') {
  if (value && typeof value === 'object') {
    return { en: value.en || fallback, mr: value.mr || '' };
  }
  return { en: value || fallback, mr: '' };
}

function nullableMarathi(value: any) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  const text = typeof value === 'object' ? plainText(value.mr) : value;
  return text.trim() ? text.trim() : null;
}

function plainText(value: any): string {
  if (typeof value === 'string') return value;
  if (!value || typeof value !== 'object' || !Array.isArray(value.children)) return '';
  return value.children.map((block: any) => {
    if (block.type === 'paragraph') return (block.children || []).map((mark: any) => mark.text || '').join('');
    return (block.children || []).map((item: any) => (item.children || []).map((mark: any) => mark.text || '').join('')).join('\n');
  }).join('\n');
}

export function toCard(row: any): any {
  const details = row.details || {};
  const socialLinks = {
    ...(details.socialLinks && typeof details.socialLinks === 'object' && !Array.isArray(details.socialLinks) ? details.socialLinks : {}),
    ...(row.social_links && typeof row.social_links === 'object' && !Array.isArray(row.social_links) ? row.social_links : {}),
  };
  const businessName = bilingualValue(details.businessName || row.business_name);
  const category = bilingualValue(details.category || row.category);
  const about = bilingualValue(details.about || row.description);
  const ownerName = bilingualValue(details.ownerName);
  const designation = bilingualValue(details.designation);
  const tagline = bilingualValue(details.tagline);
  if (row.business_name_mr) businessName.mr = row.business_name_mr;
  if (row.category_mr) category.mr = row.category_mr;
  if (row.description_mr && typeof about.mr !== 'object') about.mr = row.description_mr;
  if (row.owner_name_mr) ownerName.mr = row.owner_name_mr;
  if (row.designation_mr) designation.mr = row.designation_mr;
  if (row.tagline_mr) tagline.mr = row.tagline_mr;
  return {
    ...details,
    id: row.id,
    userId: row.owner_id,
    slug: row.slug,
    businessName,
    category,
    categoryId: row.global_category_id ?? null,
    ownerName,
    designation,
    tagline,
    about,
    whatsapp: details.whatsapp || row.whatsapp_number || '',
    phone: details.phone || row.phone || '',
    logo: details.logo || row.logo_url || '',
    logoPublicId: details.logoPublicId || row.logo_public_id || '',
    profileImage: details.profileImage || row.profile_image_url || '',
    profileImagePublicId: details.profileImagePublicId || row.profile_image_public_id || '',
    people: Array.isArray(row.people) ? row.people : (Array.isArray(details.people) ? details.people : []),
    address: details.address || row.address || {},
    socialLinks,
    status: row.status || (row.is_published ? 'active' : (details.status || 'draft')),
    isVerified: row.is_verified ?? details.isVerified ?? false,
    planId: row.plan_id || 'basic',
    createdAt: row.created_at,
    products: details.products || [], services: details.services || [], gallery: details.gallery || [],
    offers: details.offers || [], events: details.events || [], reviews: details.reviews || [],
    stats: { ...baseStats, ...(details.stats || {}), totalViews: Number(row.profile_views || 0) },
  };
}

export function toBusinessPerson(row: any) {
  return {
    id: row.id,
    fullName: { en: row.full_name_en || '', mr: row.full_name_mr || '' },
    designation: { en: row.designation_en || '', mr: row.designation_mr || '' },
    description: { en: row.description_en || '', mr: row.description_mr || '' },
    profileImage: row.profile_image_url || '',
    profileImagePublicId: row.profile_image_public_id || '',
    displayOrder: row.display_order ?? 0,
    isPrimary: row.is_primary === true,
    isActive: row.is_active !== false,
  };
}

export function toBusinessWrite(card: Record<string, any>, ownerId?: string, includePhone = true) {
  const name = typeof card.businessName === 'object' ? card.businessName.en || card.businessName.mr : card.businessName;
  const category = typeof card.category === 'object' ? card.category.en || card.category.mr : card.category;
  const details = { ...card };
  if(card.categoryId) delete details.category;
  delete details.categoryId;
  for (const key of ['products','services','events','offers','gallery','package','details','profile_views','profileViews','plan_id','is_verified','owner_id']) delete details[key];
  return {
    ...(ownerId ? { owner_id: ownerId } : {}),
    business_name: name || 'Untitled business', business_name_mr: nullableMarathi(card.businessName), slug: card.slug,
    ...(card.categoryId !== undefined ? {global_category_id: card.categoryId} : {}),
    category_mr: card.categoryId ? null : nullableMarathi(card.category),
    owner_name_mr: nullableMarathi(card.ownerName),
    designation_mr: nullableMarathi(card.designation),
    tagline_mr: nullableMarathi(card.tagline),
    category: card.categoryId ? null : category || null, description: plainText(typeof card.about === 'object' ? card.about.en : card.about) || plainText(typeof card.about === 'object' ? card.about.mr : '' ) || null,
    description_mr: nullableMarathi(card.about),
    logo_url: card.logo || null,
    logo_public_id: card.logoPublicId || cloudinaryPublicIdFromUrl(card.logo) || null,
    profile_image_url: card.profileImage || null,
    profile_image_public_id: card.profileImagePublicId || cloudinaryPublicIdFromUrl(card.profileImage) || null,
    ...(includePhone ? { phone: card.phone || null } : {}), whatsapp_number: card.whatsapp || null,
    address: card.address || null, social_links: card.socialLinks || null,
    status: card.status || 'draft',
    is_verified: card.isVerified ?? false,
    plan_id: card.planId || 'basic',
    is_published: card.status === 'active', details,
  };
}
