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

/** The RevenueCat project, and the id it gives the `pro` entitlement. */
const REVENUECAT_PROJECT = "proj849a55d1";
const REVENUECAT_PRO_ENTITLEMENT = "entl75d6155ff5";

/**
 * What a RevenueCat webhook [event] means for Pro, or null when it means
 * nothing: `{uid, pro, expiresAt}`. An event for another entitlement, an
 * anonymous RevenueCat id (`$RCAnonymousID:...`, a purchase made before
 * signing in) or a test event is ignored.
 */
function proFromEvent(event, now) {
  if (!event || typeof event !== "object") return null;
  const uid = event.app_user_id;
  if (!isAccount(uid)) return null;
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

/** An account RevenueCat knows by its Firebase uid, not one it made up for
 * a purchase before signing in. */
function isAccount(uid) {
  return typeof uid === "string" && uid !== "" && !uid.startsWith("$RCAnonymousID");
}

/**
 * The accounts a RevenueCat `TRANSFER` [event] moved purchases between -
 * restoring on another account moves them to it - or null for any other
 * event. Both sides are listed, each once, to be checked again with
 * RevenueCat: the event says who lost and who gained a purchase, not
 * whether either still has Pro from another one.
 */
function transferredAccounts(event) {
  if (!event || typeof event !== "object" || event.type !== "TRANSFER") return null;
  const sides = [
    ...(Array.isArray(event.transferred_from) ? event.transferred_from : []),
    ...(Array.isArray(event.transferred_to) ? event.transferred_to : []),
  ];
  return [...new Set(sides.filter(isAccount))];
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

/**
 * The session a relayed notification came from, as the agent names it:
 * letters, digits, `_`, `-` and `.`, at most 64. Anything else is dropped.
 */
function cleanSession(name) {
  if (typeof name !== "string") return "";
  return /^[A-Za-z0-9_.-]{1,64}$/.test(name) ? name : "";
}

/**
 * Whether a customer has Pro, from RevenueCat's v2 list of their active
 * entitlements: `{pro, expiresAt}`. An entitlement with no expiry is a
 * lifetime purchase.
 */
function proFromActiveEntitlements(body, now) {
  const items = (body && Array.isArray(body.items)) ? body.items : [];
  const entitlement = items.find((item) => item && item.entitlement_id === REVENUECAT_PRO_ENTITLEMENT);
  if (!entitlement) return { pro: false, expiresAt: null };
  const expiresAt = typeof entitlement.expires_at === "number" ? entitlement.expires_at : null;
  return { pro: expiresAt === null || expiresAt > now, expiresAt };
}

/** How long a synced copy outlives the end of Pro. */
const SYNC_KEPT_AFTER_PRO_MS = 365 * 24 * 60 * 60 * 1000;

/** How long before deleting it the account is warned. */
const SYNC_WARNING_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * What the daily sweep does with an account that has a synced copy:
 * `"keep"`, `"warn"` (Pro ended over eleven months ago and nobody was told),
 * `"delete"` (told at least a month ago, and Pro still not back), or
 * `"clearWarning"` (Pro came back after a warning). [lapsedAt] is when Pro
 * ended, null while it is on; [warnedAt] when the warning went out.
 */
function syncSweepAction({ pro, lapsedAt, warnedAt }, now) {
  if (pro) return warnedAt ? "clearWarning" : "keep";
  if (typeof lapsedAt !== "number") return "keep";
  if (typeof warnedAt === "number") {
    return now - warnedAt >= SYNC_WARNING_MS && now - lapsedAt >= SYNC_KEPT_AFTER_PRO_MS
      ? "delete"
      : "keep";
  }
  return now - lapsedAt >= SYNC_KEPT_AFTER_PRO_MS - SYNC_WARNING_MS ? "warn" : "keep";
}

/** What every session name the app creates starts with, as `SessionTab.ownedPrefix`. */
const OWNED_SESSION_PREFIX = "termphin_";

/**
 * A session's name the way the app shows it: without the prefix that only
 * marks the app's own sessions, as `SessionTab.displayName`.
 */
function sessionLabel(session) {
  return session.startsWith(OWNED_SESSION_PREFIX)
    ? session.slice(OWNED_SESSION_PREFIX.length)
    : session;
}

/**
 * The tag a relayed push about [session] of machine [profileId] carries on
 * Android, as `relayTag` in the app's push_service.dart: a newer push about
 * the same session replaces the older one, and the app takes it away by the
 * same tag once that session is opened.
 */
function relayTag(profileId, session) {
  return `relay:${profileId}:${session}`;
}

/**
 * The Android part of a relayed push. The system draws a push itself while the
 * app is closed, and without an icon named here it takes the launcher icon,
 * whose adaptive layer is mostly margin - the dolphin shows up tiny. The
 * status bar icon is the one the app's own notifications use, and every
 * released build has it.
 *
 * A push about a session names it after the title, as the app's own
 * notifications do, and is tagged for it ([relayTag]).
 */
function relayAndroid({ title, session, profileId } = {}) {
  return {
    priority: "high",
    notification: {
      channelId: "terminal_alerts",
      icon: "ic_stat_termphin",
      visibility: "private",
      ...(session && title ? { title: `${title} · ${sessionLabel(session)}` } : {}),
      ...(session ? { tag: relayTag(profileId || "", session) } : {}),
    },
  };
}

/**
 * The iPhone part of a relayed push: the session's name after the title, as
 * on Android and in the app's own notifications.
 */
function relayApns({ title, body, session } = {}) {
  return {
    payload: {
      aps: {
        sound: "default",
        alert: { title: session && title ? `${title} · ${sessionLabel(session)}` : title, body },
      },
    },
  };
}

/** The agent's own notification kinds, which the user can switch off. */
const NOTICE_KINDS = new Set(["finished", "quiet"]);

/**
 * What the relay sends for a notification of [kind] with [body] and [plain]
 * (the body without the quoted line), given the user's [prefs] from
 * `users/{uid}/settings/notices`: null when the user switched that kind off.
 * A program's own notification has no kind and always goes through; a
 * setting that is missing counts as on. With quoted lines off, a notice that
 * brought no plain body goes out with none, never with the line.
 */
function relayText({ kind, body, plain }, prefs) {
  if (!NOTICE_KINDS.has(kind)) return { body };
  const settings = prefs || {};
  if (settings[kind] === false) return null;
  if (settings.lines === false) return { body: typeof plain === "string" ? plain : "" };
  return { body };
}

/** Where a web purchase's Stripe customer keeps the account it belongs to. */
const STRIPE_UID_KEY = "firebase_uid";

/** Subscription states that still bill, or will once a payment goes through. */
const BILLING_STATES = new Set(["active", "trialing", "past_due", "unpaid", "paused"]);

/**
 * Cancels, at once, every subscription the account [uid] bought on the web.
 *
 * The web dashboard creates one Stripe customer per account, tagged with the
 * uid in its metadata; a deleted account must stop being charged, and once
 * it is gone nobody can reach the billing portal to stop it by hand. Nothing
 * is refunded, as when an account is deleted with a store subscription. The
 * customer and its invoices stay: they are the record of what was sold.
 *
 * [request] is `fetch`, passed in so tests answer for Stripe. Returns the ids
 * of the subscriptions cancelled; throws when Stripe refuses a call, so the
 * caller can tell that a subscription may still be billing.
 */
async function cancelStripeSubscriptions(uid, key, request = fetch) {
  const headers = { Authorization: `Bearer ${key}` };
  const call = async (method, path) => {
    const response = await request(`https://api.stripe.com/v1/${path}`, { method, headers });
    if (!response.ok) {
      throw new Error(`Stripe answered ${response.status} to ${method} ${path.split("?")[0]}`);
    }
    return response.json();
  };
  const query = `metadata['${STRIPE_UID_KEY}']:'${uid.replace(/[\\']/g, "\\$&")}'`;
  const customers = await call("GET", `customers/search?limit=10&query=${encodeURIComponent(query)}`);
  const cancelled = [];
  for (const customer of customers.data || []) {
    const subscriptions = await call(
      "GET",
      `subscriptions?status=all&limit=100&customer=${encodeURIComponent(customer.id)}`,
    );
    for (const subscription of subscriptions.data || []) {
      if (!BILLING_STATES.has(subscription.status)) continue;
      await call("DELETE", `subscriptions/${encodeURIComponent(subscription.id)}`);
      cancelled.push(subscription.id);
    }
  }
  return cancelled;
}

module.exports = {
  cancelStripeSubscriptions,
  relayAndroid,
  relayApns,
  relayTag,
  sessionLabel,
  relayText,
  syncSweepAction,
  proFromEvent,
  transferredAccounts,
  proFromActiveEntitlements,
  parseRelayKey,
  cleanText,
  cleanSession,
  ENTITLEMENT,
  REVENUECAT_PROJECT,
};
