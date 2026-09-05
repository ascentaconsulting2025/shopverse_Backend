import { Router } from 'express';
import * as controller from './inquiries.controller';
import { publicRateLimiter } from '../../middlewares/rateLimiter';

const router = Router();

router.post('/:businessId/inquiries', publicRateLimiter, controller.createInquiry);

export default router;
