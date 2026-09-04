import { Router } from 'express';
import * as controller from './inquiries.controller';

const router = Router();

router.post('/:businessId/inquiries', controller.createInquiry);

export default router;
