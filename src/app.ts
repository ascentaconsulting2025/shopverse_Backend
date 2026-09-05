import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { json, urlencoded } from 'express';
import { errorHandler } from './middlewares/errorHandler';
import routes from './routes';

const app = express();
const defaultCorsOrigins = [
  'http://localhost:3000',
  'https://shopverseindia.ascentaconsulting.in',
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

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedCorsOrigins.has(origin)) return callback(null, true);
    callback(new Error('Origin not allowed by CORS'));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.use(helmet() as any);
app.use(morgan('dev'));
app.use(json());
app.use(urlencoded({ extended: true }));

app.use('/api/v1', routes);

app.use(errorHandler);

export default app;
