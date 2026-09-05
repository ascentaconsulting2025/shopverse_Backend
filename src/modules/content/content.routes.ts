import { Router } from 'express';
import { authGuard } from '../../middlewares/authGuard';
import { validateRequest } from '../../middlewares/validateRequest';
import { eventSchema, offerSchema, gallerySchema } from './content.schema';
import { makeContentController } from './content.controller';

export const contentRoutes = (kind: 'events' | 'offers' | 'gallery', schema: any) => {
  const router = Router(); const controller = makeContentController(kind);
  router.post('/:businessId', authGuard, validateRequest(schema), controller.create);
  router.get('/:businessId', controller.list);
  router.get('/item/:id', controller.get);
  router.put('/item/:id', authGuard, validateRequest(schema.partial()), controller.update);
  router.patch('/item/:id', authGuard, validateRequest(schema.partial()), controller.update);
  router.delete('/item/:id', authGuard, controller.remove);
  return router;
};

export { eventSchema, offerSchema, gallerySchema };