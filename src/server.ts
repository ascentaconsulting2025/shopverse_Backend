import dotenv from 'dotenv';
dotenv.config();
import app from './app';
import { startCloudinaryCleanup } from './utils/cloudinaryCleanup';

const PORT = process.env.PORT || 5000;

app.listen(Number(PORT), () => {
  startCloudinaryCleanup();
  console.log(`Server listening on port ${PORT}`);
});
