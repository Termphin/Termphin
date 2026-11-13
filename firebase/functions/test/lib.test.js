const test = require("node:test");
const assert = require("node:assert/strict");
const { proFromEvent, parseRelayKey, cleanText } = require("../lib");

const now = Date.UTC(2026, 10, 13);
const later = now + 30 * 24 * 3600 * 1000;

test("a purchase grants Pro until it expires", () => {
  assert.deepEqual(
    proFromEvent(
      { type: "INITIAL_PURCHASE", app_user_id: "uid1", entitlement_ids: ["pro"], expiration_at_ms: later },
      now,
    ),
    { uid: "uid1", pro: true, expiresAt: later },
  );
});

test("a renewal that arrives after its own expiry does not grant", () => {
  assert.equal(
    proFromEvent({ type: "RENEWAL", app_user_id: "uid1", expiration_at_ms: now - 1 }, now).pro,
    false,
  );
});

test("a lifetime purchase has no expiry", () => {
  assert.deepEqual(
    proFromEvent({ type: "NON_RENEWING_PURCHASE", app_user_id: "uid1" }, now),
    { uid: "uid1", pro: true, expiresAt: null },
  );
});

test("expiration takes Pro away; cancellation alone does not", () => {
  assert.equal(proFromEvent({ type: "EXPIRATION", app_user_id: "uid1" }, now).pro, false);
  assert.equal(proFromEvent({ type: "CANCELLATION", app_user_id: "uid1" }, now), null);
  assert.equal(proFromEvent({ type: "BILLING_ISSUE", app_user_id: "uid1" }, now), null);
});

test("anonymous buyers, other entitlements and junk are ignored", () => {
  assert.equal(proFromEvent({ type: "INITIAL_PURCHASE", app_user_id: "$RCAnonymousID:abc" }, now), null);
  assert.equal(
    proFromEvent({ type: "INITIAL_PURCHASE", app_user_id: "uid1", entitlement_ids: ["other"] }, now),
    null,
  );
  assert.equal(proFromEvent({ type: "TEST", app_user_id: "uid1" }, now), null);
  assert.equal(proFromEvent(null, now), null);
  assert.equal(proFromEvent("x", now), null);
});

test("a relay key is an id and a secret, nothing else", () => {
  const id = "a".repeat(22);
  const secret = "b".repeat(43);
  assert.deepEqual(parseRelayKey(`${id}.${secret}`), { id, secret });
  assert.equal(parseRelayKey(`${id}`), null);
  assert.equal(parseRelayKey(`${id}.${secret}.x`), null);
  assert.equal(parseRelayKey(`../${id}.${secret}`), null);
  assert.equal(parseRelayKey(42), null);
});

test("text reaching a notification is one short line", () => {
  assert.equal(cleanText("a\u001b[31mb\nc"), "a [31mb c");
  assert.equal(cleanText(undefined), "");
  assert.equal(cleanText("x".repeat(500)).length, 200);
});
