"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const dotenv_1 = __importDefault(require("dotenv"));
dotenv_1.default.config();
const app_1 = __importDefault(require("./app"));
const cloudinaryCleanup_1 = require("./utils/cloudinaryCleanup");
const PORT = process.env.PORT || 5000;
app_1.default.listen(Number(PORT), () => {
    (0, cloudinaryCleanup_1.startCloudinaryCleanup)();
    console.log(`Server listening on port ${PORT}`);
});
