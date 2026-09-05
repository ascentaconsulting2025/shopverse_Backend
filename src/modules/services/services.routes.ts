import { Router } from 'express';
import * as controller from './services.controller';
import { authGuard } from '../../middlewares/authGuard';
import { validateRequest } from '../../middlewares/validateRequest';
import { createServiceSchema, updateServiceSchema } from './services.schema';

const router = Router();

router.post('/:businessId/services', authGuard, validateRequest(createServiceSchema), controller.createService);
router.get('/:businessId/services', controller.listServices);
router.get('/services/:id', controller.getService);
router.patch('/services/:id', authGuard, validateRequest(updateServiceSchema), controller.updateService);
router.delete('/services/:id', authGuard, controller.deleteService);

export default router;
