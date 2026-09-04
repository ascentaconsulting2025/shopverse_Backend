import rateLimit from 'express-rate-limit';

export const publicRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  message: JSON.stringify({ success: false, error: { message: 'Too many requests' } }),
});

export const uploadsRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  message: JSON.stringify({ success: false, error: { message: 'Too many uploads' } }),
});
