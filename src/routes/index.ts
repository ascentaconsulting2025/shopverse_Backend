import { Router } from 'express';
import authRoutes from '../modules/auth/auth.routes';
import businessRoutes from '../modules/business/business.routes';
import productsRoutes from '../modules/products/products.routes';
import inquiriesRoutes from '../modules/inquiries/inquiries.routes';

const router = Router();

router.use('/auth', authRoutes);
router.use('/businesses', businessRoutes);
router.use('/businesses', productsRoutes);
router.use('/businesses', inquiriesRoutes);

export default router;
