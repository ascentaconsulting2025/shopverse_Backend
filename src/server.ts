import dotenv from 'dotenv';
dotenv.config();
import app from './app';

const PORT = process.env.PORT || 3000;

app.listen(Number(PORT), () => {
  console.log(`Server listening on port ${PORT}`);
});
