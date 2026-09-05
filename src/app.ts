import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { json, urlencoded } from 'express';
import { errorHandler } from './middlewares/errorHandler';
import routes from './routes';

const app = express();

app.use(cors({
  origin: (origin, callback) => {
    const allowed = (process.env.CORS_ORIGIN || 'http://localhost:3000').split(',').map(value => value.trim());
    if (!origin || allowed.includes(origin)) return callback(null, true);
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
