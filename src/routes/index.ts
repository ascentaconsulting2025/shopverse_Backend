import pickupRoutes from '../modules/fulfillment/pickup.routes';
import pricingRoutes from '../modules/fulfillment/pricing.routes';
import fleetRoutes from '../modules/fleet/fleet.routes';
import businessAccessRoutes from '../modules/business-access/access.routes';
import logisticsRoutes from '../modules/logistics/logistics.routes';
import deliveryPartnerRoutes from '../modules/delivery-partners/delivery-partners.routes';
import addressRoutes from '../modules/addresses/addresses.routes';
import exploreRoutes from '../modules/explore/explore.routes';
import cartRoutes from '../modules/cart/cart.routes';
import ordersRoutes from '../modules/orders/orders.routes';
import categoryRoutes, { globalCategoryRoutes } from '../modules/categories/categories.routes';
import { Router } from 'express';
import authRoutes from '../modules/auth/auth.routes';
import businessRoutes from '../modules/business/business.routes';
import productsRoutes from '../modules/products/products.routes';
import inquiriesRoutes from '../modules/inquiries/inquiries.routes';
import servicesRoutes from '../modules/services/services.routes';
import { contentRoutes } from '../modules/content/content.routes';
import { eventSchema, offerSchema, gallerySchema } from '../modules/content/content.schema';
import uploadRoutes from '../modules/uploads/uploads.routes';

const router = Router();
router.use(businessAccessRoutes);

router.use('/fulfillment/pricing', pricingRoutes);
router.use('/fulfillment/pickup', pickupRoutes);
router.use('/fleet-types', fleetRoutes);
router.use('/logistics', logisticsRoutes);
router.use('/delivery-partners', deliveryPartnerRoutes);
router.use('/addresses', addressRoutes);
router.use('/cart', cartRoutes);
router.use('/orders', ordersRoutes);

router.use('/explore', exploreRoutes);
router.use('/categories', globalCategoryRoutes);
router.use('/auth', authRoutes);
router.use('/businesses', categoryRoutes);
router.use('/businesses', businessRoutes);
router.use('/businesses', productsRoutes);
router.use('/businesses', inquiriesRoutes);
router.use('/businesses', servicesRoutes);
router.use('/events', contentRoutes('events', eventSchema));
router.use('/offers', contentRoutes('offers', offerSchema));
router.use('/gallery', contentRoutes('gallery', gallerySchema));
router.use('/uploads', uploadRoutes);

export default router;
