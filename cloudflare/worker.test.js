import assert from "node:assert/strict";
import test from "node:test";

if (!globalThis.atob) globalThis.atob = value => Buffer.from(value, "base64").toString("binary");

const { base64UrlBytes, canonicalCard } = await import("./worker.js");

test("base64 URL values decode to their original bytes", () => {
  const encoded = Buffer.from("secure tiles").toString("base64url");
  assert.equal(Buffer.from(base64UrlBytes(encoded)).toString(), "secure tiles");
});

test("contact cards use Python-compatible canonical key ordering", () => {
  const card = { protocol: "secure-tiles-v1", type: "contact", name: "alice",
                 encryption_key: "enc", signing_key: "sign" };
  assert.equal(canonicalCard(card), '{"encryption_key":"enc","name":"alice","protocol":"secure-tiles-v1","signing_key":"sign","type":"contact"}');
});
