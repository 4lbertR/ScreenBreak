import { Router } from 'express';
import { getDb } from '../config/database.js';
import authenticate from '../middleware/auth.js';

const router = Router();

// Helper: get Monday of the current week as YYYY-MM-DD
function getCurrentWeekStart() {
  const now = new Date();
  const dayOfWeek = now.getDay(); // 0=Sunday, 1=Monday, ...
  const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
  const monday = new Date(now);
  monday.setDate(now.getDate() + mondayOffset);
  monday.setHours(0, 0, 0, 0);
  return monday.toISOString().split('T')[0];
}

// GET / - top 50 users by time saved this week
router.get('/', (req, res) => {
  try {
    const db = getDb();
    const weekStart = getCurrentWeekStart();

    // Try cache first
    let leaderboard = db.prepare(`
      SELECT user_id, username, display_name, streak_days, total_time_saved
      FROM leaderboard_cache
      WHERE week_start = ?
      ORDER BY total_time_saved DESC
      LIMIT 50
    `).all(weekStart);

    // If cache is empty, compute live from daily_stats
    if (leaderboard.length === 0) {
      const weekEnd = new Date(weekStart);
      weekEnd.setDate(weekEnd.getDate() + 6);
      const weekEndStr = weekEnd.toISOString().split('T')[0];

      leaderboard = db.prepare(`
        SELECT
          u.id AS user_id,
          u.username,
          u.display_name,
          COALESCE(SUM(ds.time_saved_seconds), 0) AS total_time_saved
        FROM users u
        INNER JOIN daily_stats ds ON ds.user_id = u.id
        WHERE ds.date >= ? AND ds.date <= ?
        GROUP BY u.id
        HAVING total_time_saved > 0
        ORDER BY total_time_saved DESC
        LIMIT 50
      `).all(weekStart, weekEndStr);

      // Add rank positions
      leaderboard = leaderboard.map((entry, index) => ({
        ...entry,
        streak_days: 0, // Live query doesn't compute streak
        rank: index + 1,
      }));
    } else {
      leaderboard = leaderboard.map((entry, index) => ({
        ...entry,
        rank: index + 1,
      }));
    }

    res.json({
      success: true,
      data: {
        week_start: weekStart,
        count: leaderboard.length,
        leaderboard,
      },
    });
  } catch (err) {
    console.error('Leaderboard error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve leaderboard',
    });
  }
});

// GET /weekly - get weekly leaderboard (same as / but explicit weekly endpoint)
router.get('/weekly', (req, res) => {
  try {
    const db = getDb();
    const weekStart = getCurrentWeekStart();
    const weekEnd = new Date(weekStart);
    weekEnd.setDate(weekEnd.getDate() + 6);
    const weekEndStr = weekEnd.toISOString().split('T')[0];

    // Always compute live for /weekly to ensure freshness
    let leaderboard = db.prepare(`
      SELECT
        u.id AS user_id,
        u.username,
        u.display_name,
        COALESCE(SUM(ds.time_saved_seconds), 0) AS total_time_saved,
        COALESCE(SUM(ds.total_unlocks), 0) AS total_unlocks,
        COUNT(ds.id) AS days_active
      FROM users u
      INNER JOIN daily_stats ds ON ds.user_id = u.id
      WHERE ds.date >= ? AND ds.date <= ?
      GROUP BY u.id
      HAVING total_time_saved > 0
      ORDER BY total_time_saved DESC
      LIMIT 50
    `).all(weekStart, weekEndStr);

    leaderboard = leaderboard.map((entry, index) => ({
      ...entry,
      rank: index + 1,
    }));

    res.json({
      success: true,
      data: {
        week_start: weekStart,
        week_end: weekEndStr,
        count: leaderboard.length,
        leaderboard,
      },
    });
  } catch (err) {
    console.error('Weekly leaderboard error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve weekly leaderboard',
    });
  }
});

// POST /refresh - recalculate leaderboard cache
router.post('/refresh', authenticate, (req, res) => {
  try {
    const db = getDb();
    const weekStart = getCurrentWeekStart();
    const weekEnd = new Date(weekStart);
    weekEnd.setDate(weekEnd.getDate() + 6);
    const weekEndStr = weekEnd.toISOString().split('T')[0];

    // Clear existing cache for this week
    db.prepare('DELETE FROM leaderboard_cache WHERE week_start = ?').run(weekStart);

    // Compute leaderboard data
    const entries = db.prepare(`
      SELECT
        u.id AS user_id,
        u.username,
        u.display_name,
        COALESCE(SUM(ds.time_saved_seconds), 0) AS total_time_saved
      FROM users u
      INNER JOIN daily_stats ds ON ds.user_id = u.id
      WHERE ds.date >= ? AND ds.date <= ?
      GROUP BY u.id
      HAVING total_time_saved > 0
      ORDER BY total_time_saved DESC
      LIMIT 50
    `).all(weekStart, weekEndStr);

    // Compute streak for each user
    const insertStmt = db.prepare(`
      INSERT INTO leaderboard_cache (user_id, username, display_name, streak_days, total_time_saved, week_start)
      VALUES (?, ?, ?, ?, ?, ?)
    `);

    const refreshTransaction = db.transaction(() => {
      for (const entry of entries) {
        // Calculate current streak for this user
        const dates = db.prepare(`
          SELECT date FROM daily_stats
          WHERE user_id = ? AND time_saved_seconds > 0
          ORDER BY date DESC
        `).all(entry.user_id);

        let streak = 0;
        if (dates.length > 0) {
          const today = new Date();
          today.setHours(0, 0, 0, 0);
          const mostRecent = new Date(dates[0].date + 'T00:00:00');
          const diffFromToday = Math.floor((today - mostRecent) / (1000 * 60 * 60 * 24));

          if (diffFromToday <= 1) {
            streak = 1;
            for (let i = 1; i < dates.length; i++) {
              const curr = new Date(dates[i - 1].date + 'T00:00:00');
              const prev = new Date(dates[i].date + 'T00:00:00');
              const gap = Math.floor((curr - prev) / (1000 * 60 * 60 * 24));
              if (gap === 1) {
                streak++;
              } else {
                break;
              }
            }
          }
        }

        insertStmt.run(
          entry.user_id,
          entry.username,
          entry.display_name,
          streak,
          entry.total_time_saved,
          weekStart
        );
      }
    });

    refreshTransaction();

    res.json({
      success: true,
      data: {
        message: 'Leaderboard cache refreshed',
        week_start: weekStart,
        entries_cached: entries.length,
      },
    });
  } catch (err) {
    console.error('Leaderboard refresh error:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to refresh leaderboard',
    });
  }
});

export default router;
