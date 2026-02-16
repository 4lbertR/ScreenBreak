import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { getDb } from '../config/database.js';
import authenticate from '../middleware/auth.js';
import { registerValidation, loginValidation } from '../middleware/validate.js';
import { body } from 'express-validator';
import { handleValidationErrors } from '../middleware/validate.js';

const router = Router();
const SALT_ROUNDS = 12;
const TOKEN_EXPIRY = '30d';

function generateToken(userId) {
  return jwt.sign({ userId }, process.env.JWT_SECRET, { expiresIn: TOKEN_EXPIRY });
}

function sanitizeUser(user) {
  return {
    id: user.id,
    username: user.username,
    email: user.email,
    display_name: user.display_name,
    created_at: user.created_at,
    updated_at: user.updated_at,
  };
}

// POST /register
router.post('/register', registerValidation, async (req, res) => {
  try {
    const { username, email, password, display_name } = req.body;
    const db = getDb();

    // Check for existing user
    const existingUser = db.prepare(
      'SELECT id FROM users WHERE username = ? COLLATE NOCASE OR email = ? COLLATE NOCASE'
    ).get(username, email);

    if (existingUser) {
      return res.status(409).json({
        success: false,
        error: 'A user with that username or email already exists',
      });
    }

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    const result = db.prepare(
      `INSERT INTO users (username, email, password_hash, display_name)
       VALUES (?, ?, ?, ?)`
    ).run(username, email, passwordHash, display_name || username);

    const user = db.prepare(
      'SELECT id, username, email, display_name, created_at, updated_at FROM users WHERE id = ?'
    ).get(result.lastInsertRowid);

    const token = generateToken(user.id);

    res.status(201).json({
      success: true,
      data: {
        token,
        user: sanitizeUser(user),
      },
    });
  } catch (err) {
    console.error('Register error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to create account',
    });
  }
});

// POST /login
router.post('/login', loginValidation, async (req, res) => {
  try {
    const { email, password } = req.body;
    const db = getDb();

    const user = db.prepare(
      'SELECT * FROM users WHERE email = ? COLLATE NOCASE'
    ).get(email);

    if (!user) {
      return res.status(401).json({
        success: false,
        error: 'Invalid email or password',
      });
    }

    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      return res.status(401).json({
        success: false,
        error: 'Invalid email or password',
      });
    }

    // Update updated_at timestamp
    db.prepare('UPDATE users SET updated_at = datetime(\'now\') WHERE id = ?').run(user.id);

    const token = generateToken(user.id);

    res.json({
      success: true,
      data: {
        token,
        user: sanitizeUser(user),
      },
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({
      success: false,
      error: 'Login failed',
    });
  }
});

// GET /me
router.get('/me', authenticate, (req, res) => {
  try {
    const db = getDb();
    const user = db.prepare(
      'SELECT id, username, email, display_name, created_at, updated_at FROM users WHERE id = ?'
    ).get(req.user.id);

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found',
      });
    }

    res.json({
      success: true,
      data: { user: sanitizeUser(user) },
    });
  } catch (err) {
    console.error('Get profile error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve profile',
    });
  }
});

// PUT /me
router.put(
  '/me',
  authenticate,
  [
    body('display_name')
      .optional()
      .trim()
      .isLength({ min: 1, max: 50 })
      .withMessage('Display name must be between 1 and 50 characters'),
    handleValidationErrors,
  ],
  (req, res) => {
    try {
      const { display_name } = req.body;
      const db = getDb();

      if (display_name === undefined) {
        return res.status(400).json({
          success: false,
          error: 'No fields to update. Provide display_name.',
        });
      }

      db.prepare(
        `UPDATE users SET display_name = ?, updated_at = datetime('now') WHERE id = ?`
      ).run(display_name, req.user.id);

      const user = db.prepare(
        'SELECT id, username, email, display_name, created_at, updated_at FROM users WHERE id = ?'
      ).get(req.user.id);

      res.json({
        success: true,
        data: { user: sanitizeUser(user) },
      });
    } catch (err) {
      console.error('Update profile error:', err);
      res.status(500).json({
        success: false,
        error: 'Failed to update profile',
      });
    }
  }
);

// DELETE /me
router.delete('/me', authenticate, (req, res) => {
  try {
    const db = getDb();

    // Foreign key ON DELETE CASCADE handles related rows
    const result = db.prepare('DELETE FROM users WHERE id = ?').run(req.user.id);

    if (result.changes === 0) {
      return res.status(404).json({
        success: false,
        error: 'User not found',
      });
    }

    res.json({
      success: true,
      data: { message: 'Account deleted successfully' },
    });
  } catch (err) {
    console.error('Delete account error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to delete account',
    });
  }
});

export default router;
