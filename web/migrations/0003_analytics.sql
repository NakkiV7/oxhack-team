CREATE TABLE IF NOT EXISTS analytics_weekly (
 week TEXT NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('usage','workout')),
 tag TEXT NOT NULL,
 counts TEXT NOT NULL,
 updates INTEGER NOT NULL CHECK(updates BETWEEN 1 AND 16),
 expires_at INTEGER NOT NULL,
 last_day TEXT NOT NULL,
 sequence INTEGER NOT NULL,
 PRIMARY KEY(week,kind,tag)
);
CREATE INDEX IF NOT EXISTS analytics_expiry ON analytics_weekly(expires_at);
CREATE INDEX IF NOT EXISTS analytics_quota_day ON analytics_weekly(last_day);
