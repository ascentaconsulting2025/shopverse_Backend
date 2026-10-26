import { Router } from 'express';
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

router.post('/register', validateRequest(registerSchema), controller.register);
router.post('/login', validateRequest(loginSchema), controller.login);
router.post('/admin/users', authGuard, validateRequest(adminCreateUserSchema), controller.createUser);
router.post('/refresh', controller.refresh);
router.post('/logout', controller.logout);

export default router;
