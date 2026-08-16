const MAX_REQUEST_BYTES = 2 * 1024 * 1024;
const MAX_ATTACHMENT_BYTES = 50 * 1024 * 1024;
const MAX_ATTACHMENT_CHUNKS = 50;
const MESSAGE_TTL_SECONDS = 30 * 24 * 60 * 60;
const ATTACHMENT_TTL_SECONDS = 7 * 24 * 60 * 60;
const SERVER_ACTIONS = new Set(["server.create", "server.update", "server.delete", "channel.create", "channel.update", "channel.delete",
  "role.create", "role.update", "role.delete", "member.roles", "invite.create", "invite.revoke", "invite.redeem", "message.send"]);
const ALL_PERMISSIONS = ["view_channels", "send_messages", "manage_messages", "manage_channels", "create_invites", "manage_roles", "manage_server"];

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

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}

function canonicalServerAction(action) {
  return stableJson({ protocol: action.protocol, type: action.type, action: action.action, server_id: action.server_id,
                      actor: action.actor, issued_at: action.issued_at, nonce: action.nonce, payload: action.payload });
}

async function validateServerAction(action) {
  if (!action || action.protocol !== "secure-tiles-v1" || action.type !== "server-action"
      || !SERVER_ACTIONS.has(action.action) || !/^[0-9a-f]{32}$/.test(String(action.server_id || ""))
      || !/^[0-9a-f]{32}$/.test(String(action.nonce || "")) || !action.payload
      || Math.abs(Math.floor(Date.now() / 1000) - Number(action.issued_at)) > 300) throw new Error("Invalid or expired server action");
  const key = await crypto.subtle.importKey("raw", base64UrlBytes(String(action.actor)), "Ed25519", false, ["verify"]);
  if (!await crypto.subtle.verify("Ed25519", key, base64UrlBytes(String(action.signature)), new TextEncoder().encode(canonicalServerAction(action)))) {
    throw new Error("Invalid or forged server action");
  }
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

async function serverSnapshot(id, env) {
  const server = await env.DB.prepare("SELECT * FROM servers WHERE id = ?").bind(id).first();
  if (!server) throw new Error("Server not found");
  const [roles, channels, members] = await Promise.all([
    env.DB.prepare("SELECT * FROM server_roles WHERE server_id = ? ORDER BY position").bind(id).all(),
    env.DB.prepare("SELECT * FROM server_channels WHERE server_id = ? ORDER BY position").bind(id).all(),
    env.DB.prepare("SELECT signing_key, card, roles, joined FROM server_members WHERE server_id = ? ORDER BY joined").bind(id).all(),
  ]);
  return { id: server.id, name: server.name, owner_key: server.owner_key, accent: server.accent, icon: server.icon,
    roles: roles.results.map(role => ({ ...role, permissions: JSON.parse(role.permissions) })), channels: channels.results,
    members: members.results.map(member => ({ ...member, card: JSON.parse(member.card), roles: JSON.parse(member.roles) })) };
}

async function serverPermissions(id, actor, env) {
  const server = await env.DB.prepare("SELECT owner_key FROM servers WHERE id = ?").bind(id).first();
  if (!server) throw new Error("Server not found");
  if (server.owner_key === actor) return new Set(ALL_PERMISSIONS);
  const member = await env.DB.prepare("SELECT roles FROM server_members WHERE server_id = ? AND signing_key = ?").bind(id, actor).first();
  if (!member) throw new Error("You are not a member of this server");
  const permissions = new Set();
  for (const roleId of JSON.parse(member.roles)) {
    const role = await env.DB.prepare("SELECT permissions FROM server_roles WHERE server_id = ? AND id = ?").bind(id, roleId).first();
    if (role) for (const permission of JSON.parse(role.permissions)) permissions.add(permission);
  }
  return permissions;
}

function cleanServerName(value) {
  const name = String(value || "").trim().replace(/\s+/g, " ").slice(0, 48);
  if (!name) throw new Error("Server names cannot be empty"); return name;
}
function cleanChannelName(value) {
  const name = String(value || "").trim().toLowerCase().replace(/[^a-z0-9-]+/g, "-").replace(/^-|-$/g, "").slice(0, 32);
  if (!name) throw new Error("Channel names need letters or numbers"); return name;
}

async function applyServerAction(request, env) {
  const signed = await requestJson(request); await validateServerAction(signed);
  if (await env.DB.prepare("SELECT 1 AS found FROM server_action_nonces WHERE nonce = ?").bind(signed.nonce).first()) throw new Error("Server action was already used");
  const id = signed.server_id, actor = signed.actor, payload = signed.payload, now = Math.floor(Date.now() / 1000), statements = [];
  if (signed.action === "server.create") {
    await validateCard(payload.owner_card); if (payload.owner_card.signing_key !== actor) throw new Error("Server owner identity does not match");
    statements.push(env.DB.prepare("INSERT INTO servers VALUES (?, ?, ?, ?, '', ?)").bind(id, cleanServerName(payload.name), actor, String(payload.accent || "#5865f2").slice(0, 16), now));
    statements.push(env.DB.prepare("INSERT INTO server_roles VALUES (?, 'admin', 'Admin', '#f59e0b', ?, 0)").bind(id, JSON.stringify(ALL_PERMISSIONS)));
    statements.push(env.DB.prepare("INSERT INTO server_roles VALUES (?, 'member', 'Member', '#94a3b8', ?, 1)").bind(id, JSON.stringify(["view_channels", "send_messages"])));
    statements.push(env.DB.prepare("INSERT INTO server_members VALUES (?, ?, ?, '[\"admin\"]', ?)").bind(id, actor, JSON.stringify(payload.owner_card), now));
    statements.push(env.DB.prepare("INSERT INTO server_channels VALUES (?, ?, 'general', 'text', 0, '')").bind(id, crypto.randomUUID().replaceAll("-", "")));
  } else if (signed.action === "invite.redeem") {
    const invite = await env.DB.prepare("SELECT * FROM server_invites WHERE code = ? AND server_id = ?").bind(String(payload.code), id).first();
    if (!invite || (invite.expires && invite.expires < now) || invite.uses_left === 0) throw new Error("Invite is invalid or expired");
    await validateCard(payload.member_card); if (payload.member_card.signing_key !== actor) throw new Error("Invite identity does not match");
    statements.push(env.DB.prepare("INSERT OR IGNORE INTO server_members VALUES (?, ?, ?, ?, ?)").bind(id, actor, JSON.stringify(payload.member_card), JSON.stringify([invite.role_id]), now));
    if (invite.uses_left > 0) statements.push(env.DB.prepare("UPDATE server_invites SET uses_left = uses_left - 1 WHERE code = ?").bind(invite.code));
  } else {
    const required = {"server.update":"manage_server", "server.delete":"manage_server", "channel.create":"manage_channels", "channel.update":"manage_channels", "channel.delete":"manage_channels",
      "role.create":"manage_roles", "role.update":"manage_roles", "role.delete":"manage_roles", "member.roles":"manage_roles",
      "invite.create":"create_invites", "invite.revoke":"create_invites", "message.send":"send_messages"}[signed.action];
    if (!(await serverPermissions(id, actor, env)).has(required)) throw new Error("You do not have permission for that server action");
    if (signed.action === "server.delete") {
      const server = await env.DB.prepare("SELECT owner_key FROM servers WHERE id = ?").bind(id).first();
      if (!server || server.owner_key !== actor) throw new Error("Only the server owner can delete this server");
      for (const table of ["server_invites", "server_channels", "server_members", "server_roles"]) statements.push(env.DB.prepare(`DELETE FROM ${table} WHERE server_id = ?`).bind(id));
      statements.push(env.DB.prepare("DELETE FROM servers WHERE id = ?").bind(id));
    } else if (signed.action === "message.send") {
      const channel = await env.DB.prepare("SELECT type FROM server_channels WHERE server_id = ? AND id = ?").bind(id, String(payload.channel_id || "")).first();
      if (!channel || channel.type !== "text") throw new Error("Text channel not found");
      const actorRow = await env.DB.prepare("SELECT card FROM server_members WHERE server_id = ? AND signing_key = ?").bind(id, actor).first();
      const memberRows = await env.DB.prepare("SELECT card FROM server_members WHERE server_id = ? AND signing_key != ?").bind(id, actor).all();
      const expected = new Set(memberRows.results.map(row => JSON.parse(row.card).encryption_key));
      if (!Array.isArray(payload.packets) || payload.packets.length > 500) throw new Error("Invalid server message batch");
      const actual = new Set(payload.packets.map(packet => String(packet?.to || "")));
      if (actual.size !== payload.packets.length || actual.size !== expected.size || [...actual].some(value => !expected.has(value))) throw new Error("Server message recipients do not match server members");
      const senderKey = JSON.parse(actorRow.card).encryption_key;
      for (const packet of payload.packets) {
        if (packet.protocol !== "secure-tiles-v1" || packet.type !== "message" || packet.from !== senderKey || !packet.id || !packet.ciphertext) throw new Error("Invalid server message packet");
        statements.push(env.DB.prepare("INSERT OR IGNORE INTO queue (id, recipient, packet, created) VALUES (?, ?, ?, ?)").bind(packet.id, packet.to, JSON.stringify(packet), now));
      }
    } else if (signed.action === "server.update") {
      const icon = String(payload.icon || ""); if (icon && (!icon.startsWith("data:image/") || icon.length > 100000)) throw new Error("Server icon is invalid");
      statements.push(env.DB.prepare("UPDATE servers SET name = ?, accent = ?, icon = ? WHERE id = ?").bind(cleanServerName(payload.name), String(payload.accent || "#5865f2").slice(0,16), icon, id));
    }
    else if (signed.action === "channel.create") {
      if (!["text", "voice", "category"].includes(String(payload.type || "text"))) throw new Error("Unsupported channel type");
      const count = await env.DB.prepare("SELECT COUNT(*) AS count FROM server_channels WHERE server_id = ?").bind(id).first();
      statements.push(env.DB.prepare("INSERT INTO server_channels VALUES (?, ?, ?, ?, ?, ?)").bind(id, crypto.randomUUID().replaceAll("-", ""), cleanChannelName(payload.name), String(payload.type || "text"), count.count, String(payload.topic || "").slice(0,120)));
    } else if (signed.action === "channel.update") {
      const channel = await env.DB.prepare("SELECT type FROM server_channels WHERE server_id = ? AND id = ?").bind(id, String(payload.channel_id)).first();
      if (!channel) throw new Error("Channel not found");
      const categoryId = String(payload.category_id || "");
      if (categoryId && !await env.DB.prepare("SELECT 1 AS found FROM server_channels WHERE server_id = ? AND id = ? AND (type = 'category' OR (type = 'voice' AND topic = 'category'))").bind(id, categoryId).first()) throw new Error("Category not found");
      const topic = channel.type === "text" && Object.hasOwn(payload, "category_id") ? `category:${categoryId}` : String(payload.topic || "").slice(0,120);
      statements.push(env.DB.prepare("UPDATE server_channels SET name = ?, topic = ? WHERE server_id = ? AND id = ?").bind(cleanChannelName(payload.name), topic, id, String(payload.channel_id)));
    } else if (signed.action === "channel.delete") {
      const channel = await env.DB.prepare("SELECT type FROM server_channels WHERE server_id = ? AND id = ?").bind(id, String(payload.channel_id)).first();
      if (!channel) throw new Error("Channel not found");
      const count = await env.DB.prepare("SELECT COUNT(*) AS count FROM server_channels WHERE server_id = ? AND type = 'text'").bind(id).first();
      if (channel.type === "text" && Number(count.count) <= 1) throw new Error("A server needs at least one text channel");
      statements.push(env.DB.prepare("DELETE FROM server_channels WHERE server_id = ? AND id = ?").bind(id, String(payload.channel_id)));
    } else if (signed.action === "role.create") {
      const permissions = Array.from(new Set(payload.permissions || [])); if (permissions.some(value => !ALL_PERMISSIONS.includes(value))) throw new Error("Unsupported role permission");
      const count = await env.DB.prepare("SELECT COUNT(*) AS count FROM server_roles WHERE server_id = ?").bind(id).first();
      statements.push(env.DB.prepare("INSERT INTO server_roles VALUES (?, ?, ?, ?, ?, ?)").bind(id, crypto.randomUUID().replaceAll("-", ""), String(payload.name || "Role").slice(0,32), String(payload.color || "#94a3b8").slice(0,16), JSON.stringify(permissions), count.count));
    } else if (signed.action === "role.update") {
      const roleId = String(payload.role_id);
      if (!await env.DB.prepare("SELECT 1 AS found FROM server_roles WHERE server_id = ? AND id = ?").bind(id, roleId).first()) throw new Error("Role not found");
      const permissions = Array.from(new Set(payload.permissions || [])); if (permissions.some(value => !ALL_PERMISSIONS.includes(value))) throw new Error("Unsupported role permission");
      statements.push(env.DB.prepare("UPDATE server_roles SET name = ?, color = ?, permissions = ? WHERE server_id = ? AND id = ?").bind(String(payload.name || "Role").slice(0,32), String(payload.color || "#94a3b8").slice(0,16), JSON.stringify(permissions), id, roleId));
    } else if (signed.action === "role.delete") {
      const roleId = String(payload.role_id); if (["admin", "member"].includes(roleId)) throw new Error("Built-in roles cannot be deleted");
      const members = await env.DB.prepare("SELECT signing_key, roles FROM server_members WHERE server_id = ?").bind(id).all();
      statements.push(env.DB.prepare("DELETE FROM server_roles WHERE server_id = ? AND id = ?").bind(id, roleId));
      for (const member of members.results) {
        const roles = JSON.parse(member.roles).filter(value => value !== roleId);
        statements.push(env.DB.prepare("UPDATE server_members SET roles = ? WHERE server_id = ? AND signing_key = ?").bind(JSON.stringify(roles.length ? roles : ["member"]), id, member.signing_key));
      }
    } else if (signed.action === "member.roles") {
      const server = await env.DB.prepare("SELECT owner_key FROM servers WHERE id = ?").bind(id).first();
      if (String(payload.member) === server.owner_key) throw new Error("The server owner's roles cannot be changed");
      const roles = Array.from(new Set(payload.roles || [])); if (!roles.length) throw new Error("Member roles are invalid");
      for (const roleId of roles) if (!await env.DB.prepare("SELECT 1 AS found FROM server_roles WHERE server_id = ? AND id = ?").bind(id, roleId).first()) throw new Error("Member roles are invalid");
      statements.push(env.DB.prepare("UPDATE server_members SET roles = ? WHERE server_id = ? AND signing_key = ?").bind(JSON.stringify(roles), id, String(payload.member)));
    } else if (signed.action === "invite.create") {
      const roleId = String(payload.role_id || "member"); if (!await env.DB.prepare("SELECT 1 AS found FROM server_roles WHERE server_id = ? AND id = ?").bind(id, roleId).first()) throw new Error("Invite role is invalid");
      const code = String(payload.code); if (!/^[A-Za-z0-9_-]{4,32}$/.test(code)) throw new Error("Invite codes need 4-32 letters, numbers, dashes, or underscores");
      if (await env.DB.prepare("SELECT 1 AS found FROM server_invites WHERE code = ?").bind(code).first()) throw new Error("That invite code is already in use");
      const requestedExpiry = Number(payload.expires ?? now + 86400), expires = requestedExpiry === 0 ? 0 : Math.min(requestedExpiry, now + 2592000);
      statements.push(env.DB.prepare("INSERT INTO server_invites VALUES (?, ?, ?, ?, ?, ?)").bind(code, id, roleId, actor, expires, Math.max(-1, Math.min(100, Number(payload.uses ?? -1)))));
    }
    else if (signed.action === "invite.revoke") statements.push(env.DB.prepare("DELETE FROM server_invites WHERE code = ? AND server_id = ?").bind(String(payload.code), id));
    else throw new Error("Server action is not implemented");
  }
  statements.push(env.DB.prepare("INSERT INTO server_action_nonces VALUES (?, ?)").bind(signed.nonce, now)); await env.DB.batch(statements);
  if (signed.action === "server.delete") return json({ deleted: true, id });
  return json(await serverSnapshot(id, env));
}

async function serversForMember(signingKey, env) {
  const rows = await env.DB.prepare("SELECT server_id FROM server_members WHERE signing_key = ? ORDER BY joined").bind(signingKey).all();
  return json({ servers: await Promise.all(rows.results.map(row => serverSnapshot(row.server_id, env))) });
}

async function cleanup(env) {
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare("DELETE FROM queue WHERE created < ?").bind(now - MESSAGE_TTL_SECONDS).run();
  await env.DB.prepare("DELETE FROM typing WHERE updated < ?").bind(now - 10).run();
  await env.DB.prepare("DELETE FROM presence WHERE updated < ?").bind(now - 90).run();
  await env.DB.prepare("DELETE FROM server_action_nonces WHERE created < ?").bind(now - 600).run();
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
      if (request.method === "POST" && (url.pathname === "/v1/servers/action" || url.pathname === "/v1/servers/messages")) return await applyServerAction(request, env);
      if (request.method === "GET" && parts.length === 3 && parts[0] === "v1" && parts[1] === "servers" && parts[2].startsWith("member/")) return await serversForMember(parts[2].slice(7), env);
      if (request.method === "GET" && parts.length === 4 && parts[0] === "v1" && parts[1] === "servers" && parts[2] === "member") return await serversForMember(parts[3], env);
      if (request.method === "GET" && parts.length === 3 && parts[0] === "v1" && parts[1] === "servers") return json(await serverSnapshot(parts[2], env));
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

export { base64UrlBytes, canonicalCard, canonicalServerAction, stableJson };
