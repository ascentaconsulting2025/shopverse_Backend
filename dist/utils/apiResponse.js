"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.apiFail = exports.apiSuccess = void 0;
const apiSuccess = (data) => ({ success: true, data });
exports.apiSuccess = apiSuccess;
const apiFail = (message, code) => ({ success: false, error: { code, message } });
exports.apiFail = apiFail;
