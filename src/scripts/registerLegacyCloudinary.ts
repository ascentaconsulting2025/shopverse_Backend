/** Optional, conservative lookup of existing managed uploads; never parse a URL. */
import cloudinary from '../config/cloudinary';
import { supabaseAdmin } from '../config/supabaseClient';

async function main() {
  const fields = [
    ['businesses','logo_url','logo_public_id'],
    ['businesses','profile_image_url','profile_image_public_id'],
    ['business_people','profile_image_url','profile_image_public_id'],
    ['products','image_url','image_public_id'],
    ['services','cover_image','cover_image_public_id'],
    ['events','poster_url','poster_public_id'],
    ['offers','image_url','image_public_id'],
    ['gallery_photos','image_url','image_public_id'],
  ];
  let verified = 0, skipped = 0;
  for (const [table,urlColumn,idColumn] of fields) {
    for (let offset = 0; ; offset += 100) {
      const { data, error } = await supabaseAdmin.from(table).select('*').order('id').range(offset, offset + 99);
      if (error) throw new Error(`Cannot read ${table}`);
      for (const row of data || []) {
        const publicId = row[idColumn];
        if (!publicId || !row[urlColumn] || row.deleted_at) { skipped++; continue; }
        const existing = await supabaseAdmin.from('cloudinary_assets').select('public_id').eq('public_id', publicId).maybeSingle();
        if (existing.error) throw new Error('Cannot read upload ledger; apply migration 016 first');
        if (existing.data) continue;
        let ownerId = row.owner_id;
        if (table !== 'businesses') {
          const owner = await supabaseAdmin.from('businesses').select('owner_id').eq('id', row.business_id).single();
          if (owner.error) throw new Error('Cannot verify business owner');
          ownerId = owner.data.owner_id;
        }
        try {
          const asset = await cloudinary.api.resource(publicId, { resource_type: 'image', type: 'upload', context: true });
          if (asset.public_id !== publicId || asset.secure_url !== row[urlColumn] ||
              asset.context?.custom?.owner_id !== ownerId) { skipped++; continue; }
          const saved = await supabaseAdmin.from('cloudinary_assets').insert({
            public_id: asset.public_id, secure_url: asset.secure_url, owner_id: ownerId,
          });
          if (saved.error) throw new Error('Could not register verified legacy asset');
          verified++;
        } catch { skipped++; console.warn('Legacy image requires manual review', { table, id: row.id }); }
      }
      if (!data || data.length < 100) break;
    }
  }
  console.info('Legacy image verification complete', { verified, skipped });
}
main().catch(() => { console.error('Legacy verification stopped; check database/configuration'); process.exitCode = 1; });
