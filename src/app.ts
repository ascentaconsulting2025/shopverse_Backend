import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { json, urlencoded } from 'express';
import { errorHandler } from './middlewares/errorHandler';
import routes from './routes';

const app = express();
// Opt in only to deployment-owned proxy addresses, so forwarded client IPs are trusted narrowly.
const trustedProxies = (process.env.TRUSTED_PROXY_CIDRS || '').split(',').map(value => value.trim()).filter(Boolean);
if (trustedProxies.length) app.set('trust proxy', trustedProxies);
// Render routes public requests through its load balancer. Trust only the
// immediately connected proxy unless explicit trusted proxy ranges are set.
else if (process.env.RENDER === 'true') app.set('trust proxy', 1);
const defaultCorsOrigins = [
  'http://localhost:3000',
  'http://localhost:3001',
  'http://localhost:3002',
  'https://www.1identity.in',
];

const normalizeOrigin = (value: string) => {
  try {
    const url = new URL(value.trim());
    if (!['http:', 'https:'].includes(url.protocol) || url.pathname !== '/' && url.pathname !== '') return null;
    return url.origin;
  } catch {
    return null;
  }
};

const configuredCorsOrigins = (process.env.CORS_ORIGIN || '')
  .split(',')
  .map(normalizeOrigin)
  .filter((origin): origin is string => origin !== null);
const allowedCorsOrigins = new Set([...defaultCorsOrigins, ...configuredCorsOrigins]);
const isAllowedCorsOrigin = (origin: string) => {
  if (allowedCorsOrigins.has(origin)) return true;
  try {
    const url = new URL(origin);
    return url.protocol === 'https:' &&
      (url.hostname === '1identity.in' || url.hostname.endsWith('.1identity.in')) &&
      !url.port;
  } catch {
    return false;
  }
};

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || isAllowedCorsOrigin(origin)) return callback(null, true);
    callback(new Error('Origin not allowed by CORS'));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.use(helmet() as any);
app.use(morgan('dev'));
app.use(json());
app.use(urlencoded({ extended: true }));

// Credential-bearing mutations must originate from a configured frontend.
app.use('/api/v1/auth', (req, res, next) => {
  res.setHeader('Cache-Control', 'no-store');
  const origin = req.headers.origin;
  if (req.method !== 'GET' && req.method !== 'OPTIONS' &&
      (origin ? !isAllowedCorsOrigin(origin) : !!req.headers.cookie || req.headers['sec-fetch-site'] === 'cross-site')) {
    return res.status(403).json({ success: false, error: { message: 'Untrusted authentication origin' } });
  }
  next();
});
app.use('/api/v1', routes);

app.use(errorHandler);

export default app;
