/**
 * The decisions behind the functions, kept apart from Firebase so they can
 * be tested on their own.
 */

/** RevenueCat events that leave the subscriber with Pro. */
const GRANTING = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
  "NON_RENEWING_PURCHASE",
  "SUBSCRIPTION_EXTENDED",
  "TEMPORARY_ENTITLEMENT_GRANT",
]);

/** Events that end it. A cancellation only stops the renewal; the paid
 * period runs on, so it changes nothing until EXPIRATION arrives. */
const REVOKING = new Set(["EXPIRATION"]);

/** The entitlement RevenueCat is configured with. */
const ENTITLEMENT = "pro";

/**
 * What a RevenueCat webhook [event] means for Pro, or null when it means
 * nothing: `{uid, pro, expiresAt}`. An event for another entitlement, an
 * anonymous RevenueCat id (`$RCAnonymousID:...`, a purchase made before
 * signing in) or a test event is ignored.
 */
function proFromEvent(event, now) {
  if (!event || typeof event !== "object") return null;
  const uid = event.app_user_id;
  if (typeof uid !== "string" || uid === "" || uid.startsWith("$RCAnonymousID")) {
    return null;
  }
  const entitlements = event.entitlement_ids || [];
  if (entitlements.length > 0 && !entitlements.includes(ENTITLEMENT)) return null;
  const expiresAt =
    typeof event.expiration_at_ms === "number" ? event.expiration_at_ms : null;
  if (GRANTING.has(event.type)) {
    return { uid, pro: expiresAt === null || expiresAt > now, expiresAt };
  }
  if (REVOKING.has(event.type)) {
    return { uid, pro: false, expiresAt };
  }
  return null;
}

/**
 * A relay key as the phone writes it on the server: `<id>.<secret>`, both
 * URL-safe base64. Null for anything else.
 */
function parseRelayKey(raw) {
  if (typeof raw !== "string") return null;
  const match = /^([A-Za-z0-9_-]{16,64})\.([A-Za-z0-9_-]{32,128})$/.exec(raw);
  if (!match) return null;
  return { id: match[1], secret: match[2] };
}

/** One line of at most 200 characters, no control characters. */
function cleanText(text) {
  if (typeof text !== "string") return "";
  const flat = text.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
  return flat.length <= 200 ? flat : `${flat.slice(0, 199)}…`;
}

module.exports = { proFromEvent, parseRelayKey, cleanText, ENTITLEMENT };
