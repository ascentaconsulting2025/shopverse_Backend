"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isAdminUser = isAdminUser;
exports.authGuard = authGuard;
const supabaseClient_1 = require("../config/supabaseClient");
function isAdminUser(user) {
    const adminEmails = (process.env.ADMIN_EMAILS || '')
        .split(',').map(email => email.trim().toLowerCase()).filter(Boolean);
    return !!user.email && adminEmails.includes(user.email.toLowerCase());
}
async function authGuard(req, res, next) {
    const authHeader = req.headers.authorization;
    if (!authHeader)
        return res.status(401).json({ success: false, error: { message: 'Missing auth token' } });
    const token = authHeader.replace('Bearer ', '');
    const { data, error } = await supabaseClient_1.supabaseAdmin.auth.getUser(token);
    if (error || !data.user)
        return res.status(401).json({ success: false, error: { message: 'Invalid token' } });
    req.user = data.user;
    req.isAdmin = isAdminUser(data.user);
    next();
}
