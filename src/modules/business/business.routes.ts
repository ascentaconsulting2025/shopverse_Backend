import { Router } from 'express';
import * as controller from './business.controller';
import { authGuard } from '../../middlewares/authGuard';

const router = Router();

router.get('/mine', authGuard, controller.listMyBusinesses);
router.post('/', authGuard, controller.createBusiness);
router.get('/:id/section-visibility', authGuard, controller.getSectionVisibility);
router.patch('/:id/section-visibility', authGuard, controller.updateSectionVisibility);
router.get('/:id/usage', authGuard, controller.getBusinessUsage);
router.get('/:slug', controller.getBusinessBySlug);
router.patch('/:id', authGuard, controller.updateBusiness);
router.delete('/:id', authGuard, controller.deleteBusiness);

export default router;
