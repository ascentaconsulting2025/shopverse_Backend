import { Router } from 'express';
import multer from 'multer';
import { authGuard } from '../../middlewares/authGuard';
import { uploadsRateLimiter } from '../../middlewares/rateLimiter';
import cloudinary from '../../config/cloudinary';
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

    console.info('Image selected');
    console.info('Upload started');
    console.info('Cloudinary upload request sent');

    const result = await new Promise<any>((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        { folder: 'shopverse/uploads', resource_type: 'image' },
        (error, uploadResult) => error ? reject(error) : resolve(uploadResult),
      );
      stream.end(req.file!.buffer);
    });

    console.info('Cloudinary response received');
    if (!result?.public_id) throw new Error('Cloudinary response did not include public_id.');
    console.info('public_id received');
    if (!result?.secure_url) throw new Error('Cloudinary response did not include secure_url.');
    console.info('secure_url received');

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