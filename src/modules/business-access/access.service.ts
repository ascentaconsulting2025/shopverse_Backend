import { createHash, randomBytes } from 'node:crypto';
import { Request } from 'express';
import { createClient } from '@supabase/supabase-js';
import { env } from '../../config/env';
import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';

export const businessAccessEnabled = () => process.env.BUSINESS_ACCESS_ENABLED === 'true';
export function businessDb(req: Request) {
  if (!businessAccessEnabled()) return supabaseAdmin;
  // authGuard validates both provider identity and the existing session registry.
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { headers: { Authorization: req.headers.authorization || '' } },
  });
}
export function accessError(error: any): never {
  const status = error?.code === 'P4290' ? 429 : error?.code === '42501' ? 403 : ['23505','40001','23514'].includes(error?.code) ? 409 : error?.code === '22023' ? 400 : 503;
  throw new ApiError(status === 503 ? 'Business access is unavailable. Check the access migration and configuration.' : error.message, status);
}
export async function requireBusinessAccess(businessId: string, req: any, ownerOnly = false) {
  if (!businessAccessEnabled()) {
    const { data, error } = await supabaseAdmin.from('businesses').select('owner_id').eq('id', businessId).maybeSingle();
    if (error) throw new ApiError('Business lookup unavailable',503);
    if (!data || (data.owner_id !== req.user.id && !req.isAdmin)) throw new ApiError('Business access denied',403);
    return data.owner_id === req.user.id ? 'owner' : null;
  }
  const db = businessDb(req);
  const { data: allowed, error } = await db.rpc(ownerOnly ? 'business_can_access_team' : 'business_can_manage', { p_business: businessId });
  if (error) accessError(error);
  if (!allowed) throw new ApiError('Business access denied',403);
  const role = await db.rpc('business_role',{p_business:businessId});
  if (role.error) accessError(role.error);
  return role.data as 'owner' | 'manager' | null;
}
export const hashInvitation = (token: string) => createHash('sha256').update(token).digest('hex');
export const newInvitationToken = () => randomBytes(32).toString('base64url');

type InvitationDeliveryConfig =
  | { provider: 'resend'; apiKey: string; from: string; app: string }
  | { provider: 'adapter'; endpoint: string; secret: string; app: string };

// Resend can deliver directly. The adapter contract remains available for
// deployments that centralize transactional email in a separate service.
export function invitationDeliveryConfig() {
  const apiKey = process.env.RESEND_API_KEY?.trim();
  const from = process.env.RESEND_FROM_EMAIL?.trim();
  const endpoint = process.env.BUSINESS_INVITATION_DELIVERY_URL;
  const secret = process.env.BUSINESS_INVITATION_DELIVERY_SECRET;
  const app = process.env.PUBLIC_APP_URL;
  if (!app || !/^https:\/\//.test(app)) {
    throw new ApiError('Business invitation email delivery is not configured',503);
  }
  if (apiKey || from) {
    if (!apiKey || !from || apiKey.length < 20 || from.length > 320) {
      throw new ApiError('Resend invitation email configuration is incomplete',503);
    }
    return { provider: 'resend', apiKey, from, app } satisfies InvitationDeliveryConfig;
  }
  if (endpoint && secret && endpoint.startsWith('https://')) {
    return { provider: 'adapter', endpoint, secret, app } satisfies InvitationDeliveryConfig;
  }
  throw new ApiError('Business invitation email delivery is not configured',503);
}
export async function deliverInvitation(id: string, email: string, token: string) {
  const config = invitationDeliveryConfig();
  const url = new URL('/settings', config.app);
  url.searchParams.set('section','business');
  // Fragment keeps the token out of HTTP access logs and referrers.
  url.hash = `business-invitation=${token}`;
  const acceptUrl=url.toString();
  const result = config.provider === 'resend'
    ? await fetch('https://api.resend.com/emails', {
      method:'POST',
      headers:{'Content-Type':'application/json',Authorization:`Bearer ${config.apiKey}`,'Idempotency-Key':id},
      body:JSON.stringify({
        from:config.from,to:[email],subject:'You’re invited to manage a business on 1Identity',
        html:`<h2>You’re invited to 1Identity</h2><p>You have been invited to manage a business profile.</p><p><a href="${acceptUrl}">Review and accept invitation</a></p><p>Sign in or create an account using this email address. This invitation expires and can only be accepted by the invited email.</p><p>If you did not expect this invitation, you can ignore this email.</p>`,
        text:`You have been invited to manage a business profile on 1Identity. Review and accept the invitation: ${acceptUrl}\n\nSign in or create an account using this email address. If you did not expect this invitation, ignore this email.`,
      }),signal:AbortSignal.timeout(15000),redirect:'error',
    })
    : await fetch(config.endpoint, {
      method:'POST', headers:{'Content-Type':'application/json',Authorization:`Bearer ${config.secret}`,'Idempotency-Key':id},
      body:JSON.stringify({invitationId:id,to:email,acceptUrl}),signal:AbortSignal.timeout(15000),redirect:'error',
    });
  if (!result.ok) throw new ApiError('Invitation email delivery failed. Revoke this invitation and try again.',502);
}
