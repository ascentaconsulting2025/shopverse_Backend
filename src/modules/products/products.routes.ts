import { Router } from 'express';
import * as controller from './products.controller';

const router = Router();

router.post('/:businessId/products', controller.createProduct);
router.get('/:businessId/products', controller.listProducts);
router.patch('/products/:id', controller.updateProduct);
router.delete('/products/:id', controller.deleteProduct);

export default router;
