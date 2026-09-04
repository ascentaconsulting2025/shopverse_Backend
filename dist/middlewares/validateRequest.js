"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validateRequest = void 0;
const validateRequest = (schema) => (req, res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success)
        return res.status(400).json({ success: false, error: { message: result.error.message } });
    req.body = result.data;
    next();
};
exports.validateRequest = validateRequest;
