import { body, query, validationResult } from 'express-validator';

// Middleware that checks for validation errors and returns 400 if any exist
export function handleValidationErrors(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      error: 'Validation failed',
      data: errors.array().map((e) => ({
        field: e.path,
        message: e.msg,
      })),
    });
  }
  next();
}

export const registerValidation = [
  body('username')
    .trim()
    .isLength({ min: 3, max: 30 })
    .withMessage('Username must be between 3 and 30 characters')
    .matches(/^[a-zA-Z0-9_]+$/)
    .withMessage('Username can only contain letters, numbers, and underscores'),
  body('email')
    .trim()
    .isEmail()
    .normalizeEmail()
    .withMessage('Must be a valid email address'),
  body('password')
    .isLength({ min: 8, max: 128 })
    .withMessage('Password must be between 8 and 128 characters'),
  body('display_name')
    .optional()
    .trim()
    .isLength({ min: 1, max: 50 })
    .withMessage('Display name must be between 1 and 50 characters'),
  handleValidationErrors,
];

export const loginValidation = [
  body('email')
    .trim()
    .isEmail()
    .normalizeEmail()
    .withMessage('Must be a valid email address'),
  body('password')
    .notEmpty()
    .withMessage('Password is required'),
  handleValidationErrors,
];

export const statsValidation = [
  body('date')
    .matches(/^\d{4}-\d{2}-\d{2}$/)
    .withMessage('Date must be in YYYY-MM-DD format'),
  body('total_unlocks')
    .isInt({ min: 0 })
    .withMessage('total_unlocks must be a non-negative integer'),
  body('total_ad_time_seconds')
    .isInt({ min: 0 })
    .withMessage('total_ad_time_seconds must be a non-negative integer'),
  body('apps_blocked_count')
    .isInt({ min: 0 })
    .withMessage('apps_blocked_count must be a non-negative integer'),
  body('time_saved_seconds')
    .isInt({ min: 0 })
    .withMessage('time_saved_seconds must be a non-negative integer'),
  handleValidationErrors,
];

export const unlockLogValidation = [
  body('app_name')
    .trim()
    .notEmpty()
    .withMessage('app_name is required')
    .isLength({ max: 255 })
    .withMessage('app_name must be 255 characters or fewer'),
  body('ad_duration_seconds')
    .isInt({ min: 0 })
    .withMessage('ad_duration_seconds must be a non-negative integer'),
  body('expires_at')
    .optional()
    .isISO8601()
    .withMessage('expires_at must be a valid ISO 8601 datetime'),
  handleValidationErrors,
];

export const historyQueryValidation = [
  query('start_date')
    .optional()
    .matches(/^\d{4}-\d{2}-\d{2}$/)
    .withMessage('start_date must be in YYYY-MM-DD format'),
  query('end_date')
    .optional()
    .matches(/^\d{4}-\d{2}-\d{2}$/)
    .withMessage('end_date must be in YYYY-MM-DD format'),
  query('limit')
    .optional()
    .isInt({ min: 1, max: 365 })
    .withMessage('limit must be between 1 and 365'),
  handleValidationErrors,
];
