export function slugify(input: string) {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)+/g, '')
    .slice(0, 48);
}

export function uniqueSuffix() {
  return Math.random().toString(36).slice(2, 8);
}
