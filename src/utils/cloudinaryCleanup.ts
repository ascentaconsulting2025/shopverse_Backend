import { supabaseAdmin } from '../config/supabaseClient';
import { deleteCloudinaryImage } from './cloudinaryAsset';

// Export the runner separately so failure/retry behavior can be tested without a server.
export async function runCloudinaryCleanup(db = supabaseAdmin, destroy = deleteCloudinaryImage) {
  const { data, error } = await db.rpc('claim_cloudinary_cleanup');
  if (error) throw new Error('Unable to claim Cloudinary cleanup jobs');
  for (const asset of data || []) {
    try {
      await destroy(asset.public_id, asset.public_id);
      const saved = await db.from('cloudinary_assets').update({ state: 'deleted', last_error: null })
        .eq('public_id', asset.public_id);
      if (saved.error) throw new Error('Unable to acknowledge Cloudinary cleanup');
    } catch {
      // Claim already persisted a retry deadline. Even a DB outage or process crash
      // leaves the job recoverable. Do not log provider errors containing credentials.
      console.error('Cloudinary cleanup pending retry', { publicId: asset.public_id });
      await db.from('cloudinary_assets').update({ last_error: 'Cleanup failed; automatic retry pending' })
        .eq('public_id', asset.public_id);
    }
  }
}

export function startCloudinaryCleanup() {
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try { await runCloudinaryCleanup(); }
    catch { console.error('Cloudinary cleanup worker unavailable; check migration 016 and database connectivity'); }
    finally { running = false; }
  };
  void tick();
  const timer = setInterval(() => void tick(), 15000);
  timer.unref();
  return timer;
}
