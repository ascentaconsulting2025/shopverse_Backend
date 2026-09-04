import { Router } from 'express';
import * as controller from './business.controller';

const router = Router();

router.post('/', controller.createBusiness);
router.get('/:slug', controller.getBusinessBySlug);
router.patch('/:id', controller.updateBusiness);

export default router;
