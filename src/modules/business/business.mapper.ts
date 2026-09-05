
const baseStats = { totalViews: 0, uniqueVisitors: 0, whatsappClicks: 0, callClicks: 0, websiteClicks: 0, enquiriesCount: 0, qrScans: 0, directionClicks: 0, vcardDownloads: 0 };

export function toCard(row: any): any {
  const details = row.details || {};
  return {
    ...details,
    id: row.id,
    userId: row.owner_id,
    slug: row.slug,
    businessName: details.businessName || row.business_name,
    category: details.category || row.category || '',
    about: details.about || row.description || '',
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
    business_name: name || 'Untitled business', slug: card.slug,
    category: category || null, description: typeof card.about === 'object' ? card.about.en || card.about.mr : card.about || null,
    logo_url: card.logo || null, ...(includePhone ? { phone: card.phone || null } : {}), whatsapp_number: card.whatsapp || null,
    address: card.address || null, social_links: card.socialLinks || null,
    status: card.status || 'draft',
    is_verified: card.isVerified ?? false,
    plan_id: card.planId || 'free',
    is_published: card.status === 'active', details: card,
  };
}
