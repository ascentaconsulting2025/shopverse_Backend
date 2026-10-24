"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isAdminUser = isAdminUser;
exports.authGuard = authGuard;
const session_1 = require("../modules/auth/session");
const supabaseClient_1 = require("../config/supabaseClient");
function isAdminUser(user) {
    const adminEmails = (process.env.ADMIN_EMAILS || '')
        .split(',').map(email => email.trim().toLowerCase()).filter(Boolean);
    return !!user.email && adminEmails.includes(user.email.toLowerCase());
}
async function authGuard(req, res, next) {
    res.setHeader('Cache-Control', 'private, no-store');
    const authHeader = req.headers.authorization;
    if (!authHeader)
        return res.status(401).json({ success: false, error: { message: 'Missing auth token' } });
    const match = /^Bearer ([^\s]+)$/i.exec(authHeader);
    if (!match)
        return res.status(401).json({ success: false, error: { message: 'Malformed auth token' } });
    const token = match[1];
    try {
        const { data, error } = await supabaseClient_1.supabaseAdmin.auth.getUser(token);
        if (error && (!error.status || error.status >= 500))
            return res.status(503).json({ success: false, error: { message: 'Authentication temporarily unavailable' } });
        if (error || !data.user || Date.parse(data.user.banned_until || '') > Date.now())
            return res.status(401).json({ success: false, error: { message: 'Invalid token' } });
        try {
            await (0, session_1.assertSession)(token, data.user.id);
        }
        catch (error) {
            return next(error);
        }
        req.user = data.user;
        req.isAdmin = isAdminUser(data.user);
        next();
    }
    catch (error) {
        next(error);
    }
}
