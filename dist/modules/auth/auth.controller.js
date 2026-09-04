"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.logout = exports.login = exports.register = void 0;
const register = async (req, res, next) => {
    res.json({ success: true, data: { message: 'register stub' } });
};
exports.register = register;
const login = async (req, res, next) => {
    res.json({ success: true, data: { message: 'login stub' } });
};
exports.login = login;
const logout = async (req, res, next) => {
    res.json({ success: true, data: { message: 'logout stub' } });
};
exports.logout = logout;
