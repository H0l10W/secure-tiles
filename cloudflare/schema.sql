CREATE TABLE IF NOT EXISTS users (
  name TEXT PRIMARY KEY COLLATE NOCASE,
  encryption_key TEXT UNIQUE NOT NULL,
  signing_key TEXT UNIQUE NOT NULL,
  card TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS queue (
  id TEXT PRIMARY KEY,
  recipient TEXT NOT NULL,
  packet TEXT NOT NULL,
  created INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS queue_recipient_created ON queue(recipient, created);

CREATE TABLE IF NOT EXISTS attachments (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL,
  recipient TEXT NOT NULL,
  total_size INTEGER NOT NULL,
  chunks INTEGER NOT NULL,
  created INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS attachment_chunks (
  attachment_id TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  data TEXT NOT NULL,
  PRIMARY KEY (attachment_id, chunk_index)
);
