"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const helmet_1 = __importDefault(require("helmet"));
const morgan_1 = __importDefault(require("morgan"));
const express_2 = require("express");
const errorHandler_1 = require("./middlewares/errorHandler");
const routes_1 = __importDefault(require("./routes"));
const app = (0, express_1.default)();
const defaultCorsOrigins = [
    'http://localhost:3000',
    'https://shopverseindia.ascentaconsulting.in',
];
const normalizeOrigin = (value) => {
    try {
        const url = new URL(value.trim());
        if (!['http:', 'https:'].includes(url.protocol) || url.pathname !== '/' && url.pathname !== '')
            return null;
        return url.origin;
    }
    catch {
        return null;
    }
};
const configuredCorsOrigins = (process.env.CORS_ORIGIN || '')
    .split(',')
    .map(normalizeOrigin)
    .filter((origin) => origin !== null);
const allowedCorsOrigins = new Set([...defaultCorsOrigins, ...configuredCorsOrigins]);
app.use((0, cors_1.default)({
    origin: (origin, callback) => {
        if (!origin || allowedCorsOrigins.has(origin))
            return callback(null, true);
        callback(new Error('Origin not allowed by CORS'));
    },
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.use((0, helmet_1.default)());
app.use((0, morgan_1.default)('dev'));
app.use((0, express_2.json)());
app.use((0, express_2.urlencoded)({ extended: true }));
app.use('/api/v1', routes_1.default);
app.use(errorHandler_1.errorHandler);
exports.default = app;
