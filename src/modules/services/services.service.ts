import { supabaseAdmin } from '../../config/supabaseClient';
import { ApiError } from '../../utils/apiError';
import { cloudinaryPublicIdFromUrl } from '../../utils/cloudinaryAsset';

export const serviceSelect = '*';

export const requireService = async (id: string) => {
  const { data, error } = await supabaseAdmin.from('services').select(serviceSelect).eq('id', id).single();
  if (error || !data) throw new ApiError('Service not found', 404);
  return data;
};

export const servicesService = {
  async list(businessId: string) {
    const { data, error } = await supabaseAdmin
      .from('services')
      .select(serviceSelect)
      .eq('business_id', businessId)
      .order('created_at', { ascending: false });
    if (error) throw new ApiError(error.message, 400);
    return data || [];
  },

  async create(businessId: string, input: any) {
    const { data, error } = await supabaseAdmin.from('services').insert({
      business_id: businessId,
      name: input.name.en || input.name.mr,
      name_en: input.name.en,
      name_mr: input.name.mr,
      starting_price: input.startingPrice,
      duration_en: input.duration?.en || null,
      duration_mr: input.duration?.mr || null,
      category_en: input.category?.en || null,
      category_mr: input.category?.mr || null,
      details: input.description?.en || input.description?.mr || null,
      details_en: input.description?.en || null,
      details_mr: input.description?.mr || null,
      cover_image: input.image || null,
      cover_image_public_id: input.imagePublicId || cloudinaryPublicIdFromUrl(input.image) || null,
    }).select(serviceSelect).single();
    if (error) throw new ApiError(error.message, 400);
    return data;
  },

  async update(id: string, input: any) {
    const update: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (input.name !== undefined) {
      update.name = input.name.en || input.name.mr;
      update.name_en = input.name.en;
      update.name_mr = input.name.mr;
    }
    if (input.startingPrice !== undefined) update.starting_price = input.startingPrice;
    if (input.duration !== undefined) {
      update.duration_en = input.duration?.en || null;
      update.duration_mr = input.duration?.mr || null;
    }
    if (input.category !== undefined) {
      update.category_en = input.category?.en || null;
      update.category_mr = input.category?.mr || null;
    }
    if (input.description !== undefined) {
      update.details = input.description?.en || input.description?.mr || null;
      update.details_en = input.description?.en || null;
      update.details_mr = input.description?.mr || null;
    }
    if (input.image !== undefined) {
      update.cover_image = input.image || null;
      update.cover_image_public_id = input.imagePublicId || cloudinaryPublicIdFromUrl(input.image) || null;
    }

    const { data, error } = await supabaseAdmin.from('services').update(update).eq('id', id).select(serviceSelect).single();
    if (error || !data) throw new ApiError(error?.message || 'Service not found', error ? 400 : 404);
    return data;
  },

  async remove(id: string) {
    const { error } = await supabaseAdmin.from('services').delete().eq('id', id);
    if (error) throw new ApiError(error.message, 400);
  },
};
