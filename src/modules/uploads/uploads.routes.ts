import { randomUUID } from 'node:crypto';
import { imageDimensions } from '../../utils/imageDimensions';
import imageSpecs from '../../config/imageSpecs.json';
import { Router } from 'express';
import multer from 'multer';
import { authGuard } from '../../middlewares/authGuard';
import { uploadsRateLimiter } from '../../middlewares/rateLimiter';
import cloudinary from '../../config/cloudinary';
import { supabaseAdmin } from '../../config/supabaseClient';
import { apiSuccess } from '../../utils/apiResponse';

const router = Router();
const MAX_FILE_SIZE = 10 * 1024 * 1024;
const supportedMimeTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_SIZE },
  fileFilter: (_req, file, callback) => {
    if (!supportedMimeTypes.has(file.mimetype)) {
      const error = new Error('Only JPG, PNG, and WEBP images are supported.');
      (error as Error & { status?: number }).status = 400;
      callback(error);
      return;
    }
    callback(null, true);
  },
});

router.post('/', authGuard, uploadsRateLimiter, upload.single('image'), async (req, res, next) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: { message: 'An image file is required.' } });
    }

    const imageType = req.body.imageType as keyof typeof imageSpecs;
    if (!Object.prototype.hasOwnProperty.call(imageSpecs, imageType)) return res.status(400).json({ success: false, error: { message: 'A valid imageType is required.' } });
    const spec = imageSpecs[imageType];
    const dimensions = imageDimensions(req.file.buffer);
    if (!dimensions || dimensions.width !== spec.width || dimensions.height !== spec.height) {
      return res.status(422).json({ success: false, error: { message: `Image must be cropped to ${spec.width} × ${spec.height} pixels.` } });
    }
    console.info('Image selected');
    console.info('Upload started');
    console.info('Cloudinary upload request sent');

    // Reserve a unique server-owned ID before contacting Cloudinary. If upload or
    // the following DB write times out, the durable ledger still covers the orphan.
    const uploadId = randomUUID();
    const publicId = `shopverse/uploads/${uploadId}`;
    const reserved = await supabaseAdmin.from('cloudinary_assets').insert({
      public_id: publicId, secure_url: `pending:${uploadId}`, owner_id: (req as any).user.id,
    });
    if (reserved.error) throw new Error('Unable to register uploaded image. Please try again.');
    const result = await new Promise<any>((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        { folder: 'shopverse/uploads', public_id: uploadId, overwrite: false, context: { owner_id: (req as any).user.id, image_type: imageType }, resource_type: 'image', allowed_formats: ['jpg', 'jpeg', 'png', 'webp'] },
        (error, uploadResult) => error ? reject(error) : resolve(uploadResult),
      );
      stream.end(req.file!.buffer);
    });

    console.info('Cloudinary response received');
    if (result?.public_id !== publicId) throw new Error('Cloudinary response did not match the reserved public_id.');
    console.info('public_id received');
    if (!result?.secure_url) throw new Error('Cloudinary response did not include secure_url.');
    console.info('secure_url received');

    const registered = await supabaseAdmin.from('cloudinary_assets')
      .update({ secure_url: result.secure_url }).eq('public_id', result.public_id);
    if (registered.error) throw new Error('Unable to save uploaded image metadata. Cleanup is queued.');

    if (result.width !== spec.width || result.height !== spec.height || !['jpg', 'jpeg', 'png', 'webp'].includes(result.format)) {
      await supabaseAdmin.from('cloudinary_assets').update({ cleanup_after: new Date().toISOString() }).eq('public_id', result.public_id);
      return res.status(422).json({ success: false, error: { message: 'Image processing failed. Please try another image.' } });
    }
    const response = {
      secure_url: result.secure_url,
      public_id: result.public_id,
      resource_type: result.resource_type,
      format: result.format,
      width: result.width,
      height: result.height,
      bytes: result.bytes,
    };
    console.info('Upload verified');
    console.info('Uploaded Cloudinary image displayed');
    return res.json(apiSuccess(response));
  } catch (error) {
    return next(error);
  }
});

export default router;