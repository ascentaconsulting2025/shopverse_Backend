"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.slugify = slugify;
exports.uniqueSuffix = uniqueSuffix;
function slugify(input) {
    return input
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/(^-|-$)+/g, '')
        .slice(0, 48);
}
function uniqueSuffix() {
    return Math.random().toString(36).slice(2, 8);
}
