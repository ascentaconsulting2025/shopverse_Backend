import dotenv from 'dotenv';
dotenv.config();
import app from './app';
import { startDeliveryWorker } from './modules/logistics/worker';
import { startCloudinaryCleanup } from './utils/cloudinaryCleanup';

const PORT = process.env.PORT || 5000;

app.listen(Number(PORT), () => {
  startCloudinaryCleanup();
  startDeliveryWorker();
  console.log(`Server listening on port ${PORT}`);
});
