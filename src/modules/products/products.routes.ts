import { Router } from 'express';
import * as controller from './products.controller';
import { authGuard } from '../../middlewares/authGuard';
import { validateRequest } from '../../middlewares/validateRequest';
import { createProductSchema, updateProductSchema } from './products.schema';

const router = Router();

router.post('/:businessId/products', authGuard, validateRequest(createProductSchema), controller.createProduct);
router.get('/:businessId/products', controller.listProducts);
router.get('/products/:id', controller.getProduct);
router.patch('/products/:id', authGuard, validateRequest(updateProductSchema), controller.updateProduct);
router.delete('/products/:id', authGuard, controller.deleteProduct);

export default router;
