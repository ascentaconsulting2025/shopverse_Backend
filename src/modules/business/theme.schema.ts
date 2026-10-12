import { z } from 'zod';

const color = z.string().regex(/^#[0-9a-f]{6}$/i, 'Use a six-digit hex colour');
export const themeConfigSchema = z.object({
  version: z.literal(1),
  theme: z.enum(['modern-glass', 'minimal-executive', 'dark-elegant']),
  primary: color, secondary: color, accent: color, background: color,
  text: color, surface: color, border: color,
  glass: z.enum(['off', 'light', 'medium', 'strong']),
  cardStyle: z.enum(['solid', 'glass', 'outlined']),
  radius: z.enum(['sharp', 'rounded', 'pill']),
  shadow: z.enum(['off', 'soft', 'strong']),
  header: z.enum(['standard', 'floating', 'transparent', 'minimal']),
  font: z.enum(['Inter', 'DM Sans', 'Plus Jakarta Sans']),
  section: z.enum(['card', 'glass', 'outlined']),
}).strict();
