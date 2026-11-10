import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import * as controller from './auth.controller';
import { validateRequest } from '../../middlewares/validateRequest';
import { adminCreateUserSchema, loginSchema, registerSchema } from './auth.schema';
import { authGuard } from '../../middlewares/authGuard';

import * as management from './userManagement';

const router = Router();
router.post('/recovery/complete', management.recoveryLimiter, management.completeRecovery);
router.use('/admin/users', authGuard, management.requireSuperAdmin);
router.get('/admin/users', management.listUsers);
router.get('/admin/users/:id', management.userDetails);
router.post('/admin/users/:id', management.recoveryLimiter, management.mutateUser);

const otpLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 20, standardHeaders: true, legacyHeaders: false });
router.post('/verify-email', otpLimiter, controller.verifyEmail);
router.post('/register', otpLimiter, validateRequest(registerSchema), controller.register);
router.post('/google', controller.googleLogin);
router.post('/login', otpLimiter, validateRequest(loginSchema), controller.login);
router.post('/admin/users', authGuard, validateRequest(adminCreateUserSchema), controller.createUser);
router.post('/refresh', controller.refresh);
router.post('/logout', controller.logout);

export default router;
