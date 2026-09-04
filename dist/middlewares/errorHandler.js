"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.errorHandler = errorHandler;
function errorHandler(err, req, res, next) {
    console.error(err);
    res.status(err.status || 500).json({ success: false, error: { message: err.message || 'Internal Server Error' } });
}
