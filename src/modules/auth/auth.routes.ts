import { Router } from 'express';
import * as controller from './auth.controller';
import { validateRequest } from '../../middlewares/validateRequest';
import { adminCreateUserSchema, loginSchema, registerSchema } from './auth.schema';
import { authGuard } from '../../middlewares/authGuard';

const router = Router();

router.post('/register', validateRequest(registerSchema), controller.register);
router.post('/login', validateRequest(loginSchema), controller.login);
router.post('/admin/users', authGuard, validateRequest(adminCreateUserSchema), controller.createUser);
router.post('/logout', controller.logout);

export default router;
