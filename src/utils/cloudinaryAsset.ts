import cloudinary from '../config/cloudinary';

// Historical URL parsing was ambiguous (transformations, dotted IDs, other clouds).
// Only upload responses registered by the backend authorize asset destruction.
export function cloudinaryPublicIdFromUrl(_value: unknown): null { return null; }

export async function deleteCloudinaryImage(publicId: string, _imageId: string) {
  const result = await cloudinary.uploader.destroy(publicId, {
    resource_type: 'image', type: 'upload', invalidate: true,
  });
  if (!['ok', 'not found'].includes(result.result)) {
    throw new Error(`Cloudinary deletion returned ${result.result || 'unknown'}`);
  }
  return result.result;
}
