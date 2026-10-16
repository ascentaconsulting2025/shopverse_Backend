import { createClient } from '@supabase/supabase-js';
import { env } from './env';

const serverAuth = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };

// Database/admin requests must never inherit a signed-in customer's session.
export const supabaseAdmin = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: serverAuth,
  global: { headers: { Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` } },
});

// A fresh client per login/registration prevents sessions leaking across requests.
export const createAuthClient = () => createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
  auth: serverAuth,
});
export const supabaseAnon = createAuthClient();
