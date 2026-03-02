CREATE TABLE scores (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  game       TEXT NOT NULL DEFAULT 'gribli',
  player_name TEXT NOT NULL,
  score      INTEGER NOT NULL,
  link       TEXT,
  device_id  TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  ip_hash    TEXT
);

CREATE INDEX idx_scores_game_score ON scores(game, score DESC);
CREATE INDEX idx_scores_device_id ON scores(device_id, created_at);
