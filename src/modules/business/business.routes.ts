import { Router } from 'express';
import * as controller from './business.controller';
import { authGuard } from '../../middlewares/authGuard';
import { validateRequest } from '../../middlewares/validateRequest';
import { businessPayloadSchema } from './business.schema';

const router = Router();

router.get('/mine', authGuard, controller.listMyBusinesses);
router.get('/count', controller.getBusinessCount);
router.post('/', authGuard, validateRequest(businessPayloadSchema), controller.createBusiness);
router.get('/:id/section-visibility', authGuard, controller.getSectionVisibility);
router.patch('/:id/section-visibility', authGuard, controller.updateSectionVisibility);
router.get('/:id/usage', authGuard, controller.getBusinessUsage);
router.get('/:slug', controller.getBusinessBySlug);
router.patch('/:id', authGuard, validateRequest(businessPayloadSchema), controller.updateBusiness);
router.delete('/:id', authGuard, controller.deleteBusiness);

export default router;
