import assert from "node:assert/strict";
import test from "node:test";

if (!globalThis.atob) globalThis.atob = value => Buffer.from(value, "base64").toString("binary");

const { base64UrlBytes, canonicalCard, canonicalServerAction, stableJson } = await import("./worker.js");

test("base64 URL values decode to their original bytes", () => {
  const encoded = Buffer.from("secure tiles").toString("base64url");
  assert.equal(Buffer.from(base64UrlBytes(encoded)).toString(), "secure tiles");
});

test("server actions use recursive Python-compatible canonical JSON", () => {
  const action = { protocol: "secure-tiles-v1", type: "server-action", action: "channel.create",
    server_id: "a".repeat(32), actor: "actor", issued_at: 1, nonce: "b".repeat(32),
    payload: { type: "text", name: "general", rules: ["send", "view"] } };
  assert.equal(canonicalServerAction(action), stableJson(action));
  assert.equal(stableJson({ z: { b: 2, a: 1 }, a: true }), '{"a":true,"z":{"a":1,"b":2}}');
});

test("contact cards use Python-compatible canonical key ordering", () => {
  const card = { protocol: "secure-tiles-v1", type: "contact", name: "alice",
                 encryption_key: "enc", signing_key: "sign" };
  assert.equal(canonicalCard(card), '{"encryption_key":"enc","name":"alice","protocol":"secure-tiles-v1","signing_key":"sign","type":"contact"}');
});
