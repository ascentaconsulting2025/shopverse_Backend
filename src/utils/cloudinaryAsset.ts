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
