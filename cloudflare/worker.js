const MAX_REQUEST_BYTES = 2 * 1024 * 1024;
const MAX_ATTACHMENT_BYTES = 50 * 1024 * 1024;
const MAX_ATTACHMENT_CHUNKS = 50;
const MESSAGE_TTL_SECONDS = 30 * 24 * 60 * 60;
const ATTACHMENT_TTL_SECONDS = 7 * 24 * 60 * 60;

function json(value, status = 200) {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
}

function base64UrlBytes(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, character => character.charCodeAt(0));
}

function canonicalCard(card) {
  return JSON.stringify({
    encryption_key: card.encryption_key,
    name: card.name,
    protocol: card.protocol,
    signing_key: card.signing_key,
    type: card.type,
  });
}

async function validateCard(card) {
  if (!card || card.protocol !== "secure-tiles-v1" || card.type !== "contact"
      || !/^[A-Za-z0-9_]{1,32}$/.test(String(card.name || ""))) {
    throw new Error("Invalid contact card");
  }
  try {
    const key = await crypto.subtle.importKey("raw", base64UrlBytes(String(card.signing_key)), "Ed25519", false, ["verify"]);
    const valid = await crypto.subtle.verify("Ed25519", key, base64UrlBytes(String(card.signature)),
                                             new TextEncoder().encode(canonicalCard(card)));
    if (!valid) throw new Error("Invalid signature");
    base64UrlBytes(String(card.encryption_key));
  } catch {
    throw new Error("Invalid or forged contact card");
  }
}

async function tokenHash(token) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}

async function requestJson(request) {
  const length = Number(request.headers.get("content-length") || "0");
  if (length > MAX_REQUEST_BYTES) throw new Error("Request is too large");
  const text = await request.text();
  if (!text || new TextEncoder().encode(text).length > MAX_REQUEST_BYTES) throw new Error("Request is too large");
  return JSON.parse(text);
}

async function register(request, env) {
  const card = await requestJson(request);
  await validateCard(card);
  const name = String(card.name).toLowerCase();
  const existing = await env.DB.prepare("SELECT signing_key FROM users WHERE name = ?").bind(name).first();
  if (existing && existing.signing_key !== card.signing_key) throw new Error("That username is already taken. Choose another one.");
  if (existing) {
    await env.DB.prepare("UPDATE users SET card = ? WHERE name = ?").bind(JSON.stringify(card), name).run();
  } else {
    await env.DB.prepare("INSERT INTO users (name, encryption_key, signing_key, card) VALUES (?, ?, ?, ?)")
      .bind(name, card.encryption_key, card.signing_key, JSON.stringify(card)).run();
  }
  return json({ ok: true });
}

async function lookup(name, env) {
  const row = await env.DB.prepare("SELECT card FROM users WHERE name = ?").bind(name.toLowerCase()).first();
  return row ? json(JSON.parse(row.card)) : json({ error: "Username not found" }, 404);
}

async function enqueue(request, env) {
  const packet = await requestJson(request);
  const required = ["protocol", "type", "id", "to", "from", "ciphertext"];
  if (required.some(key => !(key in packet)) || packet.protocol !== "secure-tiles-v1" || packet.type !== "message") {
    throw new Error("Invalid packet");
  }
  const recipient = await env.DB.prepare("SELECT 1 AS found FROM users WHERE encryption_key = ?").bind(packet.to).first();
  if (!recipient) throw new Error("Recipient is not registered");
  await env.DB.prepare("INSERT OR IGNORE INTO queue (id, recipient, packet, created) VALUES (?, ?, ?, ?)")
    .bind(packet.id, packet.to, JSON.stringify(packet), Math.floor(Date.now() / 1000)).run();
  return json({ ok: true });
}

async function setTyping(request, env) {
  const packet = await requestJson(request);
  const required = ["protocol", "type", "id", "to", "from", "ciphertext"];
  if (required.some(key => !(key in packet)) || packet.protocol !== "secure-tiles-v1" || packet.type !== "message") {
    throw new Error("Invalid typing packet");
  }
  const recipient = await env.DB.prepare("SELECT 1 AS found FROM users WHERE encryption_key = ?").bind(packet.to).first();
  if (!recipient) throw new Error("Recipient is not registered");
  await env.DB.prepare("INSERT INTO typing VALUES (?, ?, ?, ?) ON CONFLICT(sender, recipient) DO UPDATE SET packet = excluded.packet, updated = excluded.updated")
    .bind(packet.from, packet.to, JSON.stringify(packet), Math.floor(Date.now() / 1000)).run();
  return json({ ok: true });
}

async function setPresence(request, env) {
  const packet = await requestJson(request);
  const required = ["protocol", "type", "id", "to", "from", "ciphertext"];
  if (required.some(key => !(key in packet)) || packet.protocol !== "secure-tiles-v1" || packet.type !== "message") {
    throw new Error("Invalid presence packet");
  }
  const recipient = await env.DB.prepare("SELECT 1 AS found FROM users WHERE encryption_key = ?").bind(packet.to).first();
  if (!recipient) throw new Error("Recipient is not registered");
  await env.DB.prepare("INSERT INTO presence VALUES (?, ?, ?, ?) ON CONFLICT(sender, recipient) DO UPDATE SET packet = excluded.packet, updated = excluded.updated")
    .bind(packet.from, packet.to, JSON.stringify(packet), Math.floor(Date.now() / 1000)).run();
  return json({ ok: true });
}

async function drain(recipient, env) {
  const now = Math.floor(Date.now() / 1000);
  const rows = await env.DB.prepare("SELECT id, packet FROM queue WHERE recipient = ? ORDER BY created LIMIT 100")
    .bind(recipient).all();
  const typing = await env.DB.prepare("SELECT packet FROM typing WHERE recipient = ? AND updated >= ?")
    .bind(recipient, now - 5).all();
  const presence = await env.DB.prepare("SELECT packet FROM presence WHERE recipient = ? AND updated >= ?")
    .bind(recipient, now - 45).all();
  if (rows.results.length) {
    await env.DB.batch(rows.results.map(row => env.DB.prepare("DELETE FROM queue WHERE id = ?").bind(row.id)));
  }
  return json({ messages: rows.results.map(row => JSON.parse(row.packet)),
                typing: typing.results.map(row => JSON.parse(row.packet)),
                presence: presence.results.map(row => JSON.parse(row.packet)) });
}

async function attachmentAction(id, action, request, env) {
  if (!/^[A-Za-z0-9-]{1,64}$/.test(id)) throw new Error("Invalid attachment identifier");
  const body = await requestJson(request);
  const token = String(body.token || "");
  if (base64UrlBytes(token).length < 16) throw new Error("Invalid attachment transfer");
  const hash = await tokenHash(token);

  if (action === "begin") {
    const totalSize = Number(body.total_size), chunks = Number(body.chunks);
    if (!Number.isInteger(totalSize) || !Number.isInteger(chunks) || totalSize < 1
        || totalSize > MAX_ATTACHMENT_BYTES || chunks < 1 || chunks > MAX_ATTACHMENT_CHUNKS) {
      throw new Error("Invalid attachment size");
    }
    const existing = await env.DB.prepare("SELECT * FROM attachments WHERE id = ?").bind(id).first();
    if (existing) {
      if (existing.token_hash !== hash || existing.recipient !== body.recipient
          || existing.total_size !== totalSize || existing.chunks !== chunks) {
        throw new Error("Attachment upload does not match its existing transfer");
      }
    } else {
      await env.DB.prepare("INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?)")
        .bind(id, hash, String(body.recipient), totalSize, chunks, Math.floor(Date.now() / 1000)).run();
    }
    return json({ ok: true });
  }

  const transfer = await env.DB.prepare("SELECT token_hash, chunks FROM attachments WHERE id = ?").bind(id).first();
  if (!transfer || transfer.token_hash !== hash) throw new Error("Invalid attachment transfer");
  if (action === "status") {
    const rows = await env.DB.prepare("SELECT chunk_index FROM attachment_chunks WHERE attachment_id = ? ORDER BY chunk_index")
      .bind(id).all();
    return json({ received: rows.results.map(row => Number(row.chunk_index)) });
  }
  if (action === "complete") {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM attachment_chunks WHERE attachment_id = ?").bind(id),
      env.DB.prepare("DELETE FROM attachments WHERE id = ?").bind(id),
    ]);
    return json({ ok: true });
  }
  const index = Number(body.index);
  if (!Number.isInteger(index) || index < 0 || index >= transfer.chunks) throw new Error("Invalid attachment transfer");
  if (action === "chunk") {
    const data = String(body.data || "");
    if (!data || data.length > 1_500_000 || !/^[A-Za-z0-9_-]+={0,2}$/.test(data)) throw new Error("Invalid attachment chunk");
    await env.DB.prepare("INSERT OR IGNORE INTO attachment_chunks VALUES (?, ?, ?)").bind(id, index, data).run();
    return json({ ok: true });
  }
  if (action === "download") {
    const row = await env.DB.prepare("SELECT data FROM attachment_chunks WHERE attachment_id = ? AND chunk_index = ?")
      .bind(id, index).first();
    return row ? json({ data: row.data }) : json({ error: "Attachment chunk is unavailable" }, 400);
  }
  return json({ error: "Not found" }, 404);
}

async function cleanup(env) {
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare("DELETE FROM queue WHERE created < ?").bind(now - MESSAGE_TTL_SECONDS).run();
  await env.DB.prepare("DELETE FROM typing WHERE updated < ?").bind(now - 10).run();
  await env.DB.prepare("DELETE FROM presence WHERE updated < ?").bind(now - 90).run();
  const expired = await env.DB.prepare("SELECT id FROM attachments WHERE created < ? LIMIT 100")
    .bind(now - ATTACHMENT_TTL_SECONDS).all();
  for (const row of expired.results) {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM attachment_chunks WHERE attachment_id = ?").bind(row.id),
      env.DB.prepare("DELETE FROM attachments WHERE id = ?").bind(row.id),
    ]);
  }
}

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      const parts = url.pathname.split("/").filter(Boolean).map(decodeURIComponent);
      if (request.method === "GET" && url.pathname === "/health") return json({ ok: true, service: "secure-tiles-relay" });
      if (request.method === "PUT" && url.pathname === "/v1/users") return await register(request, env);
      if (request.method === "GET" && parts.length === 3 && parts[0] === "v1" && parts[1] === "users") return await lookup(parts[2], env);
      if (request.method === "POST" && url.pathname === "/v1/messages") return await enqueue(request, env);
      if (request.method === "POST" && url.pathname === "/v1/typing") return await setTyping(request, env);
      if (request.method === "POST" && url.pathname === "/v1/presence") return await setPresence(request, env);
      if (request.method === "GET" && parts.length === 3 && parts[0] === "v1" && parts[1] === "messages") return await drain(parts[2], env);
      if (request.method === "POST" && parts.length === 4 && parts[0] === "v1" && parts[1] === "attachments") {
        return await attachmentAction(parts[2], parts[3], request, env);
      }
      return json({ error: "Not found" }, 404);
    } catch (error) {
      return json({ error: error instanceof Error ? error.message : "Request failed" }, 400);
    }
  },
  async scheduled(_event, env, ctx) { ctx.waitUntil(cleanup(env)); },
};

export { base64UrlBytes, canonicalCard };
