const test = require("node:test");
const assert = require("node:assert/strict");
const { proFromEvent, parseRelayKey, cleanText, relayAndroid, relayText } = require("../lib");

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

test("a session name passes through only when it is a plain name", () => {
  const { cleanSession } = require("../lib");
  assert.equal(cleanSession("termphin_6d79be"), "termphin_6d79be");
  assert.equal(cleanSession("../etc"), "");
  assert.equal(cleanSession("a b"), "");
  assert.equal(cleanSession(42), "");
  assert.equal(cleanSession("x".repeat(65)), "");
});

test("Pro is read from RevenueCat's active entitlements", () => {
  const { proFromActiveEntitlements } = require("../lib");
  const now = Date.UTC(2026, 10, 14);
  const pro = (expires_at) => ({ items: [{ entitlement_id: "entl75d6155ff5", expires_at }] });
  assert.deepEqual(proFromActiveEntitlements(pro(now + 1000), now), { pro: true, expiresAt: now + 1000 });
  assert.deepEqual(proFromActiveEntitlements(pro(null), now), { pro: true, expiresAt: null });
  assert.deepEqual(proFromActiveEntitlements(pro(now - 1), now), { pro: false, expiresAt: now - 1 });
  assert.deepEqual(proFromActiveEntitlements({ items: [] }, now), { pro: false, expiresAt: null });
  assert.deepEqual(proFromActiveEntitlements(null, now), { pro: false, expiresAt: null });
  assert.deepEqual(
    proFromActiveEntitlements({ items: [{ entitlement_id: "other", expires_at: null }] }, now),
    { pro: false, expiresAt: null },
  );
});

test("a synced copy is kept a year after Pro ends, with a warning a month before", () => {
  const { syncSweepAction } = require("../lib");
  const day = 24 * 60 * 60 * 1000;
  const now = Date.UTC(2027, 10, 14);
  assert.equal(syncSweepAction({ pro: true }, now), "keep");
  assert.equal(syncSweepAction({ pro: true, warnedAt: now - day }, now), "clearWarning");
  assert.equal(syncSweepAction({ pro: false, lapsedAt: now - 300 * day }, now), "keep");
  assert.equal(syncSweepAction({ pro: false, lapsedAt: now - 336 * day }, now), "warn");
  assert.equal(
    syncSweepAction({ pro: false, lapsedAt: now - 340 * day, warnedAt: now - 4 * day }, now),
    "keep",
  );
  assert.equal(
    syncSweepAction({ pro: false, lapsedAt: now - 366 * day, warnedAt: now - 31 * day }, now),
    "delete",
  );
  assert.equal(
    syncSweepAction({ pro: false, lapsedAt: now - 400 * day, warnedAt: now - 10 * day }, now),
    "keep",
  );
  assert.equal(syncSweepAction({ pro: false, lapsedAt: null }, now), "keep");
});

test("a relayed push names the status bar icon, not the launcher icon", () => {
  assert.equal(relayAndroid().notification.icon, "ic_stat_termphin");
  assert.equal(relayAndroid().notification.channelId, "terminal_alerts");
  assert.equal(relayAndroid().notification.visibility, "private");
});

test("the agent's notices follow the user's settings, programs' do not", () => {
  const finished = { kind: "finished", body: "Complete! · 35s", plain: "after 35s" };
  assert.deepEqual(relayText(finished, undefined), { body: "Complete! · 35s" });
  assert.deepEqual(relayText(finished, { finished: true, lines: false }), { body: "after 35s" });
  assert.equal(relayText(finished, { finished: false }), null);
  assert.equal(relayText({ kind: "quiet", body: "x", plain: "y" }, { quiet: false }), null);
  assert.deepEqual(
    relayText({ body: "Claude is waiting" }, { finished: false, quiet: false, lines: false }),
    { body: "Claude is waiting" },
  );
  assert.deepEqual(relayText({ kind: "other", body: "b" }, { finished: false }), { body: "b" });
  assert.deepEqual(
    relayText({ kind: "finished", body: "secret line · 3s" }, { lines: false }),
    { body: "" },
  );
});
