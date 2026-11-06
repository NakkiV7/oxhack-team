PRAGMA foreign_keys=ON;
CREATE TABLE native_devices (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 auth_version INTEGER NOT NULL, public_key TEXT NOT NULL, access_hash TEXT NOT NULL UNIQUE,
 access_expires INTEGER NOT NULL, refresh_hash TEXT NOT NULL UNIQUE, refresh_expires INTEGER NOT NULL,
 mfa_at INTEGER NOT NULL
);
CREATE INDEX native_devices_user ON native_devices(user_id);
CREATE TABLE native_refresh_history (
 token_hash TEXT PRIMARY KEY, device_id TEXT NOT NULL REFERENCES native_devices(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL, reply_cipher TEXT NOT NULL, retry_until INTEGER NOT NULL, expires_at INTEGER NOT NULL,
 successor_hash TEXT NOT NULL
);
CREATE TABLE native_challenges (
 id TEXT PRIMARY KEY, device_id TEXT NOT NULL REFERENCES native_devices(id) ON DELETE CASCADE,
 token_hash TEXT NOT NULL, expires_at INTEGER NOT NULL
);
CREATE TABLE native_proof_nonces (
 device_id TEXT NOT NULL REFERENCES native_devices(id) ON DELETE CASCADE, nonce TEXT NOT NULL,
 expires_at INTEGER NOT NULL, PRIMARY KEY(device_id,nonce)
);
CREATE TABLE native_flows (id TEXT PRIMARY KEY,user_id TEXT REFERENCES users(id) ON DELETE CASCADE,stage TEXT NOT NULL,payload TEXT NOT NULL,expires_at INTEGER NOT NULL,attempts INTEGER NOT NULL DEFAULT 0);
CREATE INDEX native_flows_expiry ON native_flows(expires_at);
CREATE TABLE native_identities (provider TEXT NOT NULL,subject TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,provider_cipher TEXT,PRIMARY KEY(provider,subject));
CREATE INDEX native_identities_user ON native_identities(user_id);
CREATE TABLE native_mail_reservations (id TEXT PRIMARY KEY,day TEXT NOT NULL,month TEXT NOT NULL,recipient TEXT NOT NULL,created_at INTEGER NOT NULL);
CREATE INDEX native_mail_day ON native_mail_reservations(day);
CREATE INDEX native_mail_month ON native_mail_reservations(month);
CREATE INDEX native_mail_recipient ON native_mail_reservations(recipient,created_at);
CREATE TABLE native_plans (user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,profile_slot TEXT NOT NULL,revision INTEGER NOT NULL,preferences TEXT,programme TEXT,updated_at TEXT NOT NULL,PRIMARY KEY(user_id,profile_slot));
