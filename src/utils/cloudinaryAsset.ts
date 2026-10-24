import cloudinary from '../config/cloudinary';

export function cloudinaryPublicIdFromUrl(value: unknown) {
  if (typeof value !== 'string' || !value.includes('res.cloudinary.com/')) return null;
  try {
    const path = new URL(value).pathname;
    const marker = '/image/upload/';
    const markerIndex = path.indexOf(marker);
    if (markerIndex < 0) return null;
    const publicId = path.slice(markerIndex + marker.length).replace(/^v\d+\//, '');
    return publicId.replace(/\.[^.\/]+$/, '') || null;
  } catch {
    return null;
  }
}

export async function deleteCloudinaryImage(publicId: unknown, imageId: string) {
  if (typeof publicId !== 'string' || !publicId.trim()) return;

  const normalizedPublicId = publicId.trim();
  console.info('Cloudinary deletion started', { imageId, publicId: normalizedPublicId, resourceType: 'image' });

  try {
    const result = await cloudinary.uploader.destroy(normalizedPublicId, {
      resource_type: 'image',
      type: 'upload',
      invalidate: true,
    });

    if (result.result !== 'ok' && result.result !== 'not found') {
      throw new Error(`Cloudinary deletion returned ${result.result || 'an unknown result'}.`);
    }

    console.info('Cloudinary deletion successful', {
      imageId,
      publicId: normalizedPublicId,
      result: result.result,
    });
  } catch (error) {
    console.error('Cloudinary deletion failed', {
      imageId,
      publicId: normalizedPublicId,
      error: error instanceof Error ? error.message : error,
    });
    throw error;
  }
}

// Replacement cleanup must not remove an asset reused by another saved record.
export async function deleteUnreferencedCloudinaryImage(publicId: unknown, imageId: string) {
  if (typeof publicId !== 'string' || !publicId.trim()) return;
  const { supabaseAdmin } = await import('../config/supabaseClient');
  const references = [
    ['businesses', 'logo_public_id'], ['businesses', 'profile_image_public_id'],
    ['business_people', 'profile_image_public_id'], ['products', 'image_public_id'],
    ['services', 'cover_image_public_id'], ['gallery_photos', 'image_public_id'],
    ['events', 'poster_public_id'], ['offers', 'image_public_id'],
  ];
  for (const [table, column] of references) {
    const { data, error } = await supabaseAdmin.from(table).select('id').eq(column, publicId).limit(1);
    // A missing migration or unavailable database makes deletion unsafe.
    if (error || data?.length) return;
  }
  await deleteCloudinaryImage(publicId, imageId);
}
