import { Router } from 'express';
import * as controller from './auth.controller';
import { validateRequest } from '../../middlewares/validateRequest';
import { loginSchema, registerSchema } from './auth.schema';

const router = Router();

router.post('/register', validateRequest(registerSchema), controller.register);
router.post('/login', validateRequest(loginSchema), controller.login);
router.post('/logout', controller.logout);

export default router;
