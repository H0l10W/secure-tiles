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

CREATE TABLE IF NOT EXISTS typing (
  sender TEXT NOT NULL,
  recipient TEXT NOT NULL,
  packet TEXT NOT NULL,
  updated INTEGER NOT NULL,
  PRIMARY KEY (sender, recipient)
);

CREATE TABLE IF NOT EXISTS presence (
  sender TEXT NOT NULL,
  recipient TEXT NOT NULL,
  packet TEXT NOT NULL,
  updated INTEGER NOT NULL,
  PRIMARY KEY (sender, recipient)
);

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

CREATE TABLE IF NOT EXISTS servers (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, owner_key TEXT NOT NULL,
  accent TEXT NOT NULL, icon TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS server_members (
  server_id TEXT NOT NULL, signing_key TEXT NOT NULL, card TEXT NOT NULL,
  roles TEXT NOT NULL, joined INTEGER NOT NULL, PRIMARY KEY (server_id, signing_key)
);
CREATE INDEX IF NOT EXISTS server_members_signing ON server_members(signing_key, joined);
CREATE TABLE IF NOT EXISTS server_roles (
  server_id TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, color TEXT NOT NULL,
  permissions TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (server_id, id)
);
CREATE TABLE IF NOT EXISTS server_channels (
  server_id TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL,
  position INTEGER NOT NULL, topic TEXT NOT NULL DEFAULT '', PRIMARY KEY (server_id, id)
);
CREATE TABLE IF NOT EXISTS server_invites (
  code TEXT PRIMARY KEY, server_id TEXT NOT NULL, role_id TEXT NOT NULL,
  creator TEXT NOT NULL, expires INTEGER NOT NULL, uses_left INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS server_action_nonces (nonce TEXT PRIMARY KEY, created INTEGER NOT NULL);
