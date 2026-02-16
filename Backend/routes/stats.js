import { Router } from 'express';
import { getDb } from '../config/database.js';
import authenticate from '../middleware/auth.js';
import { statsValidation, historyQueryValidation } from '../middleware/validate.js';

const router = Router();

// POST /sync - upsert daily stats from iOS app
router.post('/sync', authenticate, statsValidation, (req, res) => {
  try {
    const { date, total_unlocks, total_ad_time_seconds, apps_blocked_count, time_saved_seconds } = req.body;
    const db = getDb();

    // Upsert: insert or replace on (user_id, date) conflict
    const stmt = db.prepare(`
      INSERT INTO daily_stats (user_id, date, total_unlocks, total_ad_time_seconds, apps_blocked_count, time_saved_seconds)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, date) DO UPDATE SET
        total_unlocks = excluded.total_unlocks,
        total_ad_time_seconds = excluded.total_ad_time_seconds,
        apps_blocked_count = excluded.apps_blocked_count,
        time_saved_seconds = excluded.time_saved_seconds
    `);

    stmt.run(req.user.id, date, total_unlocks, total_ad_time_seconds, apps_blocked_count, time_saved_seconds);

    const saved = db.prepare(
      'SELECT * FROM daily_stats WHERE user_id = ? AND date = ?'
    ).get(req.user.id, date);

    res.json({
      success: true,
      data: { stats: saved },
    });
  } catch (err) {
    console.error('Stats sync error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to sync stats',
    });
  }
});

// GET /summary - aggregated stats for user
router.get('/summary', authenticate, (req, res) => {
  try {
    const db = getDb();
    const userId = req.user.id;

    // Aggregate totals
    const totals = db.prepare(`
      SELECT
        COALESCE(SUM(total_unlocks), 0) AS total_unlocks,
        COALESCE(SUM(total_ad_time_seconds), 0) AS total_ad_time_seconds,
        COALESCE(SUM(apps_blocked_count), 0) AS total_apps_blocked,
        COALESCE(SUM(time_saved_seconds), 0) AS total_time_saved_seconds,
        COUNT(*) AS days_tracked
      FROM daily_stats
      WHERE user_id = ?
    `).get(userId);

    // Calculate current streak: consecutive days ending at today (or yesterday)
    const allDates = db.prepare(`
      SELECT date FROM daily_stats
      WHERE user_id = ? AND time_saved_seconds > 0
      ORDER BY date DESC
    `).all(userId);

    let streakDays = 0;
    if (allDates.length > 0) {
      const today = new Date();
      today.setHours(0, 0, 0, 0);

      // The most recent date the user has data for
      const mostRecent = new Date(allDates[0].date + 'T00:00:00');
      const diffFromToday = Math.floor((today - mostRecent) / (1000 * 60 * 60 * 24));

      // Streak is valid only if most recent entry is today or yesterday
      if (diffFromToday <= 1) {
        streakDays = 1;
        for (let i = 1; i < allDates.length; i++) {
          const current = new Date(allDates[i - 1].date + 'T00:00:00');
          const previous = new Date(allDates[i].date + 'T00:00:00');
          const gap = Math.floor((current - previous) / (1000 * 60 * 60 * 24));
          if (gap === 1) {
            streakDays++;
          } else {
            break;
          }
        }
      }
    }

    // Best streak ever
    let bestStreak = 0;
    if (allDates.length > 0) {
      const sortedAsc = [...allDates].reverse();
      let currentRun = 1;
      bestStreak = 1;
      for (let i = 1; i < sortedAsc.length; i++) {
        const prev = new Date(sortedAsc[i - 1].date + 'T00:00:00');
        const curr = new Date(sortedAsc[i].date + 'T00:00:00');
        const gap = Math.floor((curr - prev) / (1000 * 60 * 60 * 24));
        if (gap === 1) {
          currentRun++;
          bestStreak = Math.max(bestStreak, currentRun);
        } else {
          currentRun = 1;
        }
      }
    }

    // Average daily stats
    const daysTracked = totals.days_tracked || 1;
    const averages = {
      avg_daily_unlocks: Math.round((totals.total_unlocks / daysTracked) * 100) / 100,
      avg_daily_ad_time_seconds: Math.round((totals.total_ad_time_seconds / daysTracked) * 100) / 100,
      avg_daily_time_saved_seconds: Math.round((totals.total_time_saved_seconds / daysTracked) * 100) / 100,
    };

    res.json({
      success: true,
      data: {
        totals: {
          total_unlocks: totals.total_unlocks,
          total_ad_time_seconds: totals.total_ad_time_seconds,
          total_apps_blocked: totals.total_apps_blocked,
          total_time_saved_seconds: totals.total_time_saved_seconds,
          days_tracked: totals.days_tracked,
        },
        streaks: {
          current_streak_days: streakDays,
          best_streak_days: bestStreak,
        },
        averages,
      },
    });
  } catch (err) {
    console.error('Stats summary error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve stats summary',
    });
  }
});

// GET /history - daily stats history with optional date range
router.get('/history', authenticate, historyQueryValidation, (req, res) => {
  try {
    const db = getDb();
    const userId = req.user.id;
    const { start_date, end_date, limit } = req.query;

    let sql = 'SELECT * FROM daily_stats WHERE user_id = ?';
    const params = [userId];

    if (start_date) {
      sql += ' AND date >= ?';
      params.push(start_date);
    }
    if (end_date) {
      sql += ' AND date <= ?';
      params.push(end_date);
    }

    sql += ' ORDER BY date DESC';

    if (limit) {
      sql += ' LIMIT ?';
      params.push(parseInt(limit, 10));
    } else {
      sql += ' LIMIT 90'; // default last 90 days
    }

    const history = db.prepare(sql).all(...params);

    res.json({
      success: true,
      data: {
        count: history.length,
        history,
      },
    });
  } catch (err) {
    console.error('Stats history error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve stats history',
    });
  }
});

// GET /weekly - current week summary (Monday to Sunday)
router.get('/weekly', authenticate, (req, res) => {
  try {
    const db = getDb();
    const userId = req.user.id;

    // Compute Monday of the current week
    const now = new Date();
    const dayOfWeek = now.getDay(); // 0=Sunday, 1=Monday, ...
    const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
    const monday = new Date(now);
    monday.setDate(now.getDate() + mondayOffset);
    monday.setHours(0, 0, 0, 0);
    const weekStart = monday.toISOString().split('T')[0];

    const sunday = new Date(monday);
    sunday.setDate(monday.getDate() + 6);
    const weekEnd = sunday.toISOString().split('T')[0];

    const weeklyTotals = db.prepare(`
      SELECT
        COALESCE(SUM(total_unlocks), 0) AS total_unlocks,
        COALESCE(SUM(total_ad_time_seconds), 0) AS total_ad_time_seconds,
        COALESCE(SUM(apps_blocked_count), 0) AS total_apps_blocked,
        COALESCE(SUM(time_saved_seconds), 0) AS total_time_saved_seconds,
        COUNT(*) AS days_active
      FROM daily_stats
      WHERE user_id = ? AND date >= ? AND date <= ?
    `).get(userId, weekStart, weekEnd);

    const dailyBreakdown = db.prepare(`
      SELECT * FROM daily_stats
      WHERE user_id = ? AND date >= ? AND date <= ?
      ORDER BY date ASC
    `).all(userId, weekStart, weekEnd);

    res.json({
      success: true,
      data: {
        week_start: weekStart,
        week_end: weekEnd,
        totals: weeklyTotals,
        daily_breakdown: dailyBreakdown,
      },
    });
  } catch (err) {
    console.error('Weekly stats error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve weekly stats',
    });
  }
});

export default router;
