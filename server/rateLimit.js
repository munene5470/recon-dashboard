import rateLimit from 'express-rate-limit';

export const scanLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many scan requests. Please wait a minute and try again.' },
});

export const reportLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many report requests. Please wait a minute and try again.' },
});
