import { Router } from 'express';
import { getDb } from '../config/database.js';

const router = Router();

// GET /random - get a random motivational quote
router.get('/random', (req, res) => {
  try {
    const db = getDb();

    const quote = db.prepare(`
      SELECT id, text, author FROM motivational_quotes
      ORDER BY RANDOM()
      LIMIT 1
    `).get();

    if (!quote) {
      return res.status(404).json({
        success: false,
        error: 'No quotes available',
      });
    }

    res.json({
      success: true,
      data: { quote },
    });
  } catch (err) {
    console.error('Random quote error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve quote',
    });
  }
});

// GET /daily - get the quote of the day (deterministic by date)
router.get('/daily', (req, res) => {
  try {
    const db = getDb();

    const totalQuotes = db.prepare('SELECT COUNT(*) AS cnt FROM motivational_quotes').get().cnt;

    if (totalQuotes === 0) {
      return res.status(404).json({
        success: false,
        error: 'No quotes available',
      });
    }

    // Deterministic selection based on date:
    // Convert today's date to a number and modulo by total quotes
    const today = new Date();
    const dateString = today.toISOString().split('T')[0]; // YYYY-MM-DD
    const year = today.getFullYear();
    const month = today.getMonth() + 1;
    const day = today.getDate();

    // Simple deterministic hash from date components
    const daysSinceEpoch = Math.floor(today.getTime() / (1000 * 60 * 60 * 24));
    const index = daysSinceEpoch % totalQuotes;

    // Fetch the quote at that offset (ordered by id for consistency)
    const quote = db.prepare(`
      SELECT id, text, author FROM motivational_quotes
      ORDER BY id ASC
      LIMIT 1 OFFSET ?
    `).get(index);

    res.json({
      success: true,
      data: {
        quote,
        date: dateString,
      },
    });
  } catch (err) {
    console.error('Daily quote error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve daily quote',
    });
  }
});

export default router;
