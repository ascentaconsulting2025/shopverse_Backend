"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.supabaseAnon = exports.createAuthClient = exports.supabaseAdmin = void 0;
const supabase_js_1 = require("@supabase/supabase-js");
const env_1 = require("./env");
const serverAuth = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };
// Database/admin requests must never inherit a signed-in customer's session.
exports.supabaseAdmin = (0, supabase_js_1.createClient)(env_1.env.SUPABASE_URL, env_1.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: serverAuth,
    global: { headers: { Authorization: `Bearer ${env_1.env.SUPABASE_SERVICE_ROLE_KEY}` } },
});
// A fresh client per login/registration prevents sessions leaking across requests.
const createAuthClient = () => (0, supabase_js_1.createClient)(env_1.env.SUPABASE_URL, env_1.env.SUPABASE_ANON_KEY, {
    auth: serverAuth,
});
exports.createAuthClient = createAuthClient;
exports.supabaseAnon = (0, exports.createAuthClient)();
