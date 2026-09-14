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
