
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
  const text = typeof value === 'object' ? value.mr : value;
  return typeof text === 'string' && text.trim() ? text.trim() : null;
}

export function toCard(row: any): any {
  const details = row.details || {};
  const businessName = bilingualValue(details.businessName || row.business_name);
  const category = bilingualValue(details.category || row.category);
  const about = bilingualValue(details.about || row.description);
  const ownerName = bilingualValue(details.ownerName);
  const designation = bilingualValue(details.designation);
  const tagline = bilingualValue(details.tagline);
  if (row.business_name_mr) businessName.mr = row.business_name_mr;
  if (row.category_mr) category.mr = row.category_mr;
  if (row.description_mr) about.mr = row.description_mr;
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
    ownerName,
    designation,
    tagline,
    about,
    whatsapp: details.whatsapp || row.whatsapp_number || '',
    phone: details.phone || row.phone || '',
    logo: details.logo || row.logo_url || '',
    address: details.address || row.address || {},
    socialLinks: details.socialLinks || row.social_links || {},
    status: row.status || (row.is_published ? 'active' : (details.status || 'draft')),
    isVerified: row.is_verified ?? details.isVerified ?? false,
    planId: row.plan_id || details.planId || 'free',
    createdAt: row.created_at,
    products: details.products || [], services: details.services || [], gallery: details.gallery || [],
    offers: details.offers || [], events: details.events || [], reviews: details.reviews || [],
    stats: { ...baseStats, ...(details.stats || {}) },
  };
}

export function toBusinessWrite(card: Record<string, any>, ownerId?: string, includePhone = true) {
  const name = typeof card.businessName === 'object' ? card.businessName.en || card.businessName.mr : card.businessName;
  const category = typeof card.category === 'object' ? card.category.en || card.category.mr : card.category;
  return {
    ...(ownerId ? { owner_id: ownerId } : {}),
    business_name: name || 'Untitled business', business_name_mr: nullableMarathi(card.businessName), slug: card.slug,
    category_mr: nullableMarathi(card.category),
    owner_name_mr: nullableMarathi(card.ownerName),
    designation_mr: nullableMarathi(card.designation),
    tagline_mr: nullableMarathi(card.tagline),
    category: category || null, description: typeof card.about === 'object' ? card.about.en || card.about.mr : card.about || null,
    description_mr: nullableMarathi(card.about),
    logo_url: card.logo || null, ...(includePhone ? { phone: card.phone || null } : {}), whatsapp_number: card.whatsapp || null,
    address: card.address || null, social_links: card.socialLinks || null,
    status: card.status || 'draft',
    is_verified: card.isVerified ?? false,
    plan_id: card.planId || 'free',
    is_published: card.status === 'active', details: card,
  };
}
