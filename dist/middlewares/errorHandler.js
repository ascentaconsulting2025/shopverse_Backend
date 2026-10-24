"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.errorHandler = errorHandler;
const zod_1 = require("zod");
function errorHandler(err, req, res, next) {
    console.error(err);
    const packageStatus = /requires (?:Premium|Standard or Premium)/.test(err.message || '') ? 403 : /limit reached \(maximum \d+\)/.test(err.message || '') ? 409 : null;
    const status = packageStatus ?? (err instanceof zod_1.ZodError ? 400 : err.code === 'LIMIT_FILE_SIZE' ? 413 : (err.status || 500));
    res.status(status).json({ success: false, error: { message: err.message || 'Internal Server Error' } });
}
