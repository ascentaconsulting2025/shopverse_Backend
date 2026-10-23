import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';

export async function getBusinessPackage(businessId: string) {
  const { data, error } = await supabaseAdmin.rpc('get_business_package', { p_business: businessId });
  if (error || !data) throw new ApiError('Business package is unavailable. Please try again.', 503);
  return data as { planId: string; capabilities: Record<string, number | boolean | null>; usage: Record<string, number> };
}

export async function requirePackageFeature(businessId: string, feature: string, creating = false) {
  const pkg = await getBusinessPackage(businessId);
  const limit = pkg.capabilities[feature];
  if (limit === 0 || limit === false || limit === undefined) {
    throw new ApiError(`${feature === 'themes' ? 'Theme/template customization' : feature} requires ${feature === 'offers' || feature === 'themes' ? 'Premium' : 'Standard or Premium'}`, 403);
  }
  if (creating && typeof limit === 'number' && (pkg.usage[feature] || 0) >= limit) {
    throw new ApiError(`${feature} limit reached (maximum ${limit})`, 409);
  }
  return pkg;
}

// Existing clients send complete cards. Ignore unchanged trusted fields, reject changes.
export function protectBusinessFields(input: any, current: any, isAdmin: boolean) {
  if (!isAdmin) {
    const plan = current?.plan_id || 'basic';
    if (input.planId !== undefined && input.planId !== plan && !(input.planId === 'free' && plan === 'basic')) {
      throw new ApiError('Only an administrator can assign business packages', 403);
    }
    if (input.isVerified !== undefined && input.isVerified !== (current?.is_verified ?? false)) {
      throw new ApiError('Only an administrator can change verification', 403);
    }
  }
  // Discard client counters and nested metadata rather than persisting untrusted views.
  for (const key of ['profile_views', 'profileViews', 'details', 'owner_id', 'userId', 'is_verified', 'plan_id', 'package', 'products', 'services', 'offers', 'events', 'gallery', 'stats']) delete input[key];
  input.planId = isAdmin ? (input.planId === 'free' ? 'basic' : input.planId || current?.plan_id || 'basic') : current?.plan_id || 'basic';
  input.isVerified = isAdmin ? input.isVerified ?? current?.is_verified ?? false : current?.is_verified ?? false;
  return input;
}
