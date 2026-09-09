import dotenv from 'dotenv';
dotenv.config();
import { supabaseAdmin } from '../config/supabaseClient';

const email = process.env.DEMO_OWNER_EMAIL;
const password = process.env.DEMO_OWNER_PASSWORD;

if (!email || !password) {
  throw new Error('Set DEMO_OWNER_EMAIL and DEMO_OWNER_PASSWORD in .env before running the demo seed.');
}
const demoEmail = email;
const demoPassword = password;

async function findOrCreateOwner() {
  const { data: users, error: usersError } = await supabaseAdmin.auth.admin.listUsers({ perPage: 1000 });
  if (usersError) throw usersError;
  let user = users.users.find(item => item.email?.toLowerCase() === demoEmail.toLowerCase());
  if (!user) {
    const created = await supabaseAdmin.auth.admin.createUser({
      email: demoEmail, password: demoPassword, email_confirm: true, user_metadata: { full_name: 'One Identity Demo Owner' },
    });
    if (created.error || !created.data.user) throw created.error || new Error('Could not create demo owner');
    user = created.data.user;
  }
  const { error: profileError } = await supabaseAdmin.from('profiles').upsert({ id: user.id, full_name: 'One Identity Demo Owner' });
  if (profileError) {
    if (profileError.code === 'PGRST205') {
      throw new Error('Database schema is not installed. Run schema.sql in Supabase Dashboard → SQL Editor, then run `yarn seed:demo` again.');
    }
    throw profileError;
  }
  return user;
}

async function main() {
  const owner = await findOrCreateOwner();
  const slug = 'saraf-suvarnkar-sanstha-satara';
  const details = {
    userId: owner.id, slug,
    businessName: { en: 'Saraf & Suvarnakar Sanstha Satara', mr: 'सराफ व सुवर्णकार संस्था सातारा' },
    ownerName: { en: 'Saraf & Suvarnakar Sanstha', mr: 'सराफ व सुवर्णकार संस्था' },
    designation: { en: 'Business Association', mr: 'व्यावसायिक संघटना' },
    category: { en: 'Jewellery Association', mr: 'सराफ संघटना' },
    tagline: { en: 'Trusted jewellery businesses of Satara', mr: 'साताऱ्यातील विश्वासार्ह सराफ व्यवसाय' },
    about: { en: 'An association of certified jewellers and goldsmiths in Satara.', mr: 'साताऱ्यातील प्रमाणित सराफ आणि सुवर्णकारांची संस्था.' },
    logo: '', coverImage: '', phone: '+919000000000', whatsapp: '919000000000', email: demoEmail,
    address: { street: { en: 'Saraf Katta, Rajwada', mr: 'सराफ कट्टा, राजवाडा' }, city: { en: 'Satara', mr: 'सातारा' }, state: { en: 'Maharashtra', mr: 'महाराष्ट्र' }, pincode: '415001' },
    socialLinks: {}, templateId: 'royal-gold', themeColor: '#78350f', accentColor: '#d97706', fontFamily: 'Outfit',
    customBranding: false, status: 'active', isVerified: true, planId: 'premium',
    products: [], services: [], gallery: [], offers: [], events: [], reviews: [],
    sectionVisibility: { products: true, services: true, offers: true, gallery: true, events: true },
    stats: { totalViews: 0, uniqueVisitors: 0, whatsappClicks: 0, callClicks: 0, websiteClicks: 0, enquiriesCount: 0, qrScans: 0, directionClicks: 0, vcardDownloads: 0 },
  };
  const { error } = await supabaseAdmin.from('businesses').upsert({
    owner_id: owner.id, business_name: details.businessName.en, slug, category: details.category.en,
    description: details.about.en, phone: details.phone, whatsapp_number: details.whatsapp, address: details.address,
    social_links: details.socialLinks, is_published: true, details,
  }, { onConflict: 'slug' });
  if (error) throw error;
  console.log(`Seeded published demo card: ${slug}`);
}

main().catch(error => { console.error(error); process.exitCode = 1; });
