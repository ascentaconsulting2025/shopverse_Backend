"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.errorHandler = errorHandler;
function errorHandler(err, req, res, next) {
    console.error(err);
    const status = err.code === 'LIMIT_FILE_SIZE' ? 413 : (err.status || 500);
    res.status(status).json({ success: false, error: { message: err.message || 'Internal Server Error' } });
}
