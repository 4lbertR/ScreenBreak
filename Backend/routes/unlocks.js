import { Router } from 'express';
import { getDb } from '../config/database.js';
import authenticate from '../middleware/auth.js';
import { unlockLogValidation } from '../middleware/validate.js';

const router = Router();

// POST /log - log an unlock event from the iOS app
router.post('/log', authenticate, unlockLogValidation, (req, res) => {
  try {
    const { app_name, ad_duration_seconds, expires_at } = req.body;
    const db = getDb();

    const result = db.prepare(`
      INSERT INTO unlock_sessions (user_id, app_name, ad_duration_seconds, unlocked_at, expires_at)
      VALUES (?, ?, ?, datetime('now'), ?)
    `).run(req.user.id, app_name, ad_duration_seconds, expires_at || null);

    const session = db.prepare('SELECT * FROM unlock_sessions WHERE id = ?').get(result.lastInsertRowid);

    res.status(201).json({
      success: true,
      data: { session },
    });
  } catch (err) {
    console.error('Unlock log error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to log unlock event',
    });
  }
});

// GET /recent - last 50 unlock sessions for current user
router.get('/recent', authenticate, (req, res) => {
  try {
    const db = getDb();

    const sessions = db.prepare(`
      SELECT * FROM unlock_sessions
      WHERE user_id = ?
      ORDER BY unlocked_at DESC
      LIMIT 50
    `).all(req.user.id);

    res.json({
      success: true,
      data: {
        count: sessions.length,
        sessions,
      },
    });
  } catch (err) {
    console.error('Recent unlocks error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve recent unlocks',
    });
  }
});

// GET /stats - unlock statistics: most unlocked apps, average ad time, unlock frequency
router.get('/stats', authenticate, (req, res) => {
  try {
    const db = getDb();
    const userId = req.user.id;

    // Most unlocked apps (top 10)
    const topApps = db.prepare(`
      SELECT
        app_name,
        COUNT(*) AS unlock_count,
        COALESCE(SUM(ad_duration_seconds), 0) AS total_ad_time_seconds,
        ROUND(AVG(ad_duration_seconds), 2) AS avg_ad_duration_seconds
      FROM unlock_sessions
      WHERE user_id = ?
      GROUP BY app_name
      ORDER BY unlock_count DESC
      LIMIT 10
    `).all(userId);

    // Overall unlock stats
    const overall = db.prepare(`
      SELECT
        COUNT(*) AS total_unlocks,
        COALESCE(SUM(ad_duration_seconds), 0) AS total_ad_time_seconds,
        ROUND(AVG(ad_duration_seconds), 2) AS avg_ad_duration_seconds,
        MIN(unlocked_at) AS first_unlock,
        MAX(unlocked_at) AS last_unlock
      FROM unlock_sessions
      WHERE user_id = ?
    `).get(userId);

    // Unlock frequency by hour of day (0-23)
    const hourlyFrequency = db.prepare(`
      SELECT
        CAST(strftime('%H', unlocked_at) AS INTEGER) AS hour,
        COUNT(*) AS unlock_count
      FROM unlock_sessions
      WHERE user_id = ?
      GROUP BY hour
      ORDER BY hour ASC
    `).all(userId);

    // Unlock frequency by day of week (0=Sunday through 6=Saturday)
    const dailyFrequency = db.prepare(`
      SELECT
        CAST(strftime('%w', unlocked_at) AS INTEGER) AS day_of_week,
        COUNT(*) AS unlock_count
      FROM unlock_sessions
      WHERE user_id = ?
      GROUP BY day_of_week
      ORDER BY day_of_week ASC
    `).all(userId);

    const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const dailyFrequencyNamed = dailyFrequency.map((row) => ({
      ...row,
      day_name: dayNames[row.day_of_week],
    }));

    // Unlocks in last 7 days vs previous 7 days (trend)
    const last7 = db.prepare(`
      SELECT COUNT(*) AS count FROM unlock_sessions
      WHERE user_id = ? AND unlocked_at >= datetime('now', '-7 days')
    `).get(userId);

    const prev7 = db.prepare(`
      SELECT COUNT(*) AS count FROM unlock_sessions
      WHERE user_id = ? AND unlocked_at >= datetime('now', '-14 days') AND unlocked_at < datetime('now', '-7 days')
    `).get(userId);

    const trend = prev7.count > 0
      ? Math.round(((last7.count - prev7.count) / prev7.count) * 100)
      : (last7.count > 0 ? 100 : 0);

    res.json({
      success: true,
      data: {
        overall,
        top_apps: topApps,
        hourly_frequency: hourlyFrequency,
        daily_frequency: dailyFrequencyNamed,
        trend: {
          last_7_days: last7.count,
          previous_7_days: prev7.count,
          change_percent: trend,
        },
      },
    });
  } catch (err) {
    console.error('Unlock stats error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve unlock statistics',
    });
  }
});

export default router;
