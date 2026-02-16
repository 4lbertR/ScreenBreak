import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';

let db;

export function initDatabase(dbPath) {
  const resolvedPath = path.resolve(dbPath || process.env.DB_PATH || './data/screenbreak.db');
  const dir = path.dirname(resolvedPath);

  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  db = new Database(resolvedPath);

  // Enable WAL mode for better concurrent read performance
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  createTables();
  seedQuotes();

  return db;
}

export function getDb() {
  if (!db) {
    throw new Error('Database not initialized. Call initDatabase() first.');
  }
  return db;
}

function createTables() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE COLLATE NOCASE,
      email TEXT NOT NULL UNIQUE COLLATE NOCASE,
      password_hash TEXT NOT NULL,
      display_name TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
    CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

    CREATE TABLE IF NOT EXISTS unlock_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      app_name TEXT NOT NULL,
      ad_duration_seconds INTEGER NOT NULL DEFAULT 0,
      unlocked_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_unlock_sessions_user_id ON unlock_sessions(user_id);
    CREATE INDEX IF NOT EXISTS idx_unlock_sessions_unlocked_at ON unlock_sessions(unlocked_at);

    CREATE TABLE IF NOT EXISTS daily_stats (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      date TEXT NOT NULL,
      total_unlocks INTEGER NOT NULL DEFAULT 0,
      total_ad_time_seconds INTEGER NOT NULL DEFAULT 0,
      apps_blocked_count INTEGER NOT NULL DEFAULT 0,
      time_saved_seconds INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      UNIQUE(user_id, date)
    );

    CREATE INDEX IF NOT EXISTS idx_daily_stats_user_date ON daily_stats(user_id, date);

    CREATE TABLE IF NOT EXISTS leaderboard_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      username TEXT NOT NULL,
      display_name TEXT,
      streak_days INTEGER NOT NULL DEFAULT 0,
      total_time_saved INTEGER NOT NULL DEFAULT 0,
      week_start TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      UNIQUE(user_id, week_start)
    );

    CREATE INDEX IF NOT EXISTS idx_leaderboard_week ON leaderboard_cache(week_start, total_time_saved DESC);

    CREATE TABLE IF NOT EXISTS motivational_quotes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      text TEXT NOT NULL UNIQUE,
      author TEXT NOT NULL
    );
  `);
}

function seedQuotes() {
  const count = db.prepare('SELECT COUNT(*) AS cnt FROM motivational_quotes').get();
  if (count.cnt > 0) return;

  const quotes = [
    { text: 'The secret of getting ahead is getting started.', author: 'Mark Twain' },
    { text: 'It is not that we have a short time to live, but that we waste a good deal of it.', author: 'Seneca' },
    { text: 'Almost everything will work again if you unplug it for a few minutes, including you.', author: 'Anne Lamott' },
    { text: 'The ability to concentrate and to use time well is everything.', author: 'Lee Iacocca' },
    { text: 'You will never reach your destination if you stop and throw stones at every dog that barks.', author: 'Winston Churchill' },
    { text: 'Focus on being productive instead of busy.', author: 'Tim Ferriss' },
    { text: 'The successful warrior is the average man, with laser-like focus.', author: 'Bruce Lee' },
    { text: 'Discipline is choosing between what you want now and what you want most.', author: 'Abraham Lincoln' },
    { text: 'Your mind is a garden, your thoughts are the seeds. You can grow flowers or you can grow weeds.', author: 'William Wordsworth' },
    { text: 'Technology is a useful servant but a dangerous master.', author: 'Christian Lous Lange' },
    { text: 'The greatest weapon against stress is our ability to choose one thought over another.', author: 'William James' },
    { text: 'Do not dwell in the past, do not dream of the future, concentrate the mind on the present moment.', author: 'Buddha' },
    { text: 'Lack of direction, not lack of time, is the problem. We all have twenty-four hour days.', author: 'Zig Ziglar' },
    { text: 'The mind is everything. What you think you become.', author: 'Buddha' },
    { text: 'He who has a why to live can bear almost any how.', author: 'Friedrich Nietzsche' },
    { text: 'Be where you are, not where you think you should be.', author: 'Unknown' },
    { text: 'Disconnect to reconnect.', author: 'Unknown' },
    { text: 'Self-discipline is the magic power that makes you virtually unstoppable.', author: 'Dan Kennedy' },
    { text: 'The present moment is the only moment available to us, and it is the door to all moments.', author: 'Thich Nhat Hanh' },
    { text: 'Where focus goes, energy flows.', author: 'Tony Robbins' },
    { text: 'Starve your distractions, feed your focus.', author: 'Unknown' },
    { text: 'You cannot overestimate the unimportance of practically everything.', author: 'Greg McKeown' },
    { text: 'The price of anything is the amount of life you exchange for it.', author: 'Henry David Thoreau' },
    { text: 'What information consumes is rather obvious: it consumes the attention of its recipients.', author: 'Herbert Simon' },
    { text: 'We are what we repeatedly do. Excellence, then, is not an act, but a habit.', author: 'Aristotle' },
  ];

  const insert = db.prepare('INSERT INTO motivational_quotes (text, author) VALUES (?, ?)');
  const insertMany = db.transaction((items) => {
    for (const q of items) {
      insert.run(q.text, q.author);
    }
  });

  insertMany(quotes);
}

export default { initDatabase, getDb };
