const crypto = require("node:crypto");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { setGlobalOptions } = require("firebase-functions/v2");
const functionsV1 = require("firebase-functions/v1");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const {
  cancelStripeSubscriptions,
  syncSweepAction,
  proFromEvent,
  transferredAccounts,
  proFromActiveEntitlements,
  parseRelayKey,
  cleanText,
  cleanSession,
  relayAndroid,
  relayApns,
  relayText,
  REVENUECAT_PROJECT,
} = require("./lib");

initializeApp();
setGlobalOptions({ region: "europe-central2", maxInstances: 10 });

/** The `Authorization` header RevenueCat is configured to send. */
const revenueCatAuth = defineSecret("REVENUECAT_WEBHOOK_AUTH");

/** RevenueCat's secret API key, to forget a deleted account's customer. */
const revenueCatKey = defineSecret("REVENUECAT_SECRET_KEY");

/**
 * A restricted Stripe key (customers read, subscriptions write) to cancel a
 * deleted account's web subscriptions.
 */
const stripeKey = defineSecret("STRIPE_SECRET_KEY");

/**
 * Resend's API key, for the one email the backend sends: the warning before
 * a synced copy is deleted. `unset` turns email off, and with it the
 * deleting, which never happens without the warning.
 */
const mailKey = defineSecret("MAIL_API_KEY");
const MAIL_FROM = "Termphin <noreply@termphin.dev>";

/** Seconds between two pushes sent with one relay key. */
const RELAY_QUIET_SECONDS = 3;

/**
 * RevenueCat's webhook: the one place Pro is granted or taken away.
 *
 * The app logs in to RevenueCat with the Firebase uid, so `app_user_id` is
 * the uid. The outcome goes to two places: `users/{uid}` for the app to
 * read, and the `pro` custom claim for the security rules and the relay -
 * a client can write neither.
 *
 * Restoring purchases on another account makes RevenueCat move them there
 * and send a `TRANSFER`. Both accounts are checked with RevenueCat again on
 * the spot, so the one that gave the purchase up stops having Pro now, not
 * when its paid period would have ended. A check that fails answers 500,
 * which RevenueCat retries.
 */
exports.revenuecat = onRequest(
  { secrets: [revenueCatAuth, revenueCatKey] },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).end();
      return;
    }
    const expected = revenueCatAuth.value();
    const given = request.get("authorization") || "";
    if (!expected || !timingSafeEqual(given, expected)) {
      response.status(401).end();
      return;
    }
    const event = request.body && request.body.event;
    const moved = transferredAccounts(event);
    if (moved) {
      try {
        for (const uid of moved) {
          const checked = await proFromRevenueCat(uid);
          await setPro(uid, checked.pro, checked.expiresAt);
        }
      } catch (error) {
        console.error(`transfer check failed: ${error && error.message}`);
        response.status(500).end();
        return;
      }
      response.status(200).json({ transferred: moved.length });
      return;
    }
    const decision = proFromEvent(event, Date.now());
    if (!decision) {
      response.status(200).json({ ignored: true });
      return;
    }
    await setPro(decision.uid, decision.pro, decision.expiresAt);
    response.status(200).json({ uid: decision.uid, pro: decision.pro });
  },
);

/**
 * What a server calls to reach its owner's phones while none of them is
 * connected: `POST {key, title, body, session, kind?, plain?}`. The push
 * carries the machine the key was made for and the session, so tapping it
 * opens it. The key is made on the phone, which stored only its hash; it
 * names the user. Pro only.
 *
 * `kind` marks the helper's own notifications (`finished`, `quiet`) and
 * `plain` is their body without the quoted line: they follow the user's
 * settings in `users/{uid}/settings/notices`, read before the rate limit so
 * one switched off does not use up the window of the next.
 *
 * The text is passed through to FCM and kept nowhere.
 */
exports.relay = onRequest(guarded(async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).end();
    return;
  }
  const key = parseRelayKey(request.body && request.body.key);
  if (!key) {
    response.status(400).json({ error: "bad-key" });
    return;
  }
  const db = getFirestore();
  const keyRef = db.collection("relayKeys").doc(key.id);
  const notice = {
    kind: request.body.kind,
    body: cleanText(request.body.body),
    plain: typeof request.body.plain === "string" ? cleanText(request.body.plain) : undefined,
  };
  const allowed = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(keyRef);
    if (!snapshot.exists) return { status: 403 };
    const data = snapshot.data();
    const hash = crypto.createHash("sha256").update(key.secret).digest("hex");
    if (!timingSafeEqual(hash, data.secretHash)) return { status: 403 };
    const prefs = await tx.get(
      db.collection("users").doc(data.uid).collection("settings").doc("notices"),
    );
    const text = relayText(notice, prefs.data());
    if (!text) return { status: 200, off: true };
    const last = data.lastSentAt ? data.lastSentAt.toMillis() : 0;
    if (Date.now() - last < RELAY_QUIET_SECONDS * 1000) return { status: 429 };
    tx.update(keyRef, { lastSentAt: FieldValue.serverTimestamp() });
    return {
      status: 200,
      uid: data.uid,
      label: data.label,
      profileId: typeof data.profileId === "string" ? data.profileId : "",
      body: text.body,
    };
  });
  if (allowed.status !== 200) {
    response.status(allowed.status).end();
    return;
  }
  if (allowed.off) {
    response.status(200).json({ sent: 0, off: true });
    return;
  }
  const user = await db.collection("users").doc(allowed.uid).get();
  if (!isPro(user.data())) {
    response.status(402).json({ error: "not-pro" });
    return;
  }
  const devices = await db
    .collection("users")
    .doc(allowed.uid)
    .collection("devices")
    .get();
  const tokens = devices.docs.map((doc) => doc.data().token).filter(Boolean);
  if (tokens.length === 0) {
    response.status(200).json({ sent: 0 });
    return;
  }
  const title = cleanText(request.body.title) || allowed.label || "Termphin";
  const body = allowed.body;
  const session = cleanSession(request.body.session);
  const result = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: {
      kind: "relay",
      label: allowed.label || "",
      profileId: allowed.profileId,
      session,
      title,
    },
    android: relayAndroid({ title, session, profileId: allowed.profileId }),
    apns: relayApns({ title, body, session }),
  });
  const stale = [];
  result.responses.forEach((sent, index) => {
    const code = sent.error && sent.error.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      stale.push(devices.docs[index].ref.delete());
    }
  });
  await Promise.all(stale);
  response.status(200).json({ sent: result.successCount });
}));

/**
 * What the app calls right after a purchase, so the account has Pro before
 * RevenueCat's webhook arrives: `POST` with the account's Firebase ID token
 * as a bearer token. Asks RevenueCat for the account's active entitlements,
 * records the answer as the webhook would, and returns `{pro}`. The webhook
 * still carries renewals, cancellations and refunds while the app is closed.
 */
exports.confirmPro = onRequest({ secrets: [revenueCatKey] }, guarded(async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).end();
    return;
  }
  const header = request.get("authorization") || "";
  let uid;
  try {
    uid = (await getAuth().verifyIdToken(header.replace(/^Bearer /, ""))).uid;
  } catch (_) {
    response.status(401).end();
    return;
  }
  if (!(revenueCatKey.value() || "").trim()) {
    response.status(503).end();
    return;
  }
  let decision;
  try {
    decision = await proFromRevenueCat(uid);
  } catch (_) {
    response.status(502).end();
    return;
  }
  await setPro(uid, decision.pro, decision.expiresAt);
  response.status(200).json({ pro: decision.pro });
}));

/**
 * Whether RevenueCat says [uid] has Pro right now: `{pro, expiresAt}`. A
 * customer it does not know has none. Throws when RevenueCat could not be
 * asked or did not answer, so nothing is changed on a guess.
 */
async function proFromRevenueCat(uid) {
  const key = (revenueCatKey.value() || "").trim();
  if (!key) throw new Error("no RevenueCat key");
  const answer = await fetch(
    `https://api.revenuecat.com/v2/projects/${REVENUECAT_PROJECT}/customers/` +
      `${encodeURIComponent(uid)}/active_entitlements`,
    { headers: { Authorization: `Bearer ${key}` } },
  );
  if (answer.status === 404) return { pro: false, expiresAt: null };
  if (!answer.ok) throw new Error(`RevenueCat answered ${answer.status}`);
  return proFromActiveEntitlements(await answer.json(), Date.now());
}

/**
 * [handler] with every failure answered: a Firestore, Auth or network error
 * becomes a 500 the app can tell from a timeout, logged by its message only
 * so no request body - a notification's text, a token - reaches the logs.
 */
function guarded(handler) {
  return async (request, response) => {
    try {
      await handler(request, response);
    } catch (error) {
      console.error(`${request.path || "request"} failed: ${error && error.message}`);
      if (!response.headersSent) response.status(500).end();
    }
  };
}

function isPro(user) {
  if (!user || user.pro !== true) return false;
  if (!user.proExpiresAt) return true;
  return user.proExpiresAt.toMillis() > Date.now();
}

/**
 * Records [pro] on the account: in its document, which the relay reads, and
 * as claims on its token, which the security rules and the app read. The
 * claims carry the expiry as `proUntil` (milliseconds; absent for a
 * lifetime purchase), so a token minted before an expiry stops counting
 * at it instead of when the next webhook happens to arrive. Pro coming back
 * also clears the warning that the synced copy was about to go, so a later
 * lapse warns again rather than deleting on the old warning.
 */
async function setPro(uid, pro, expiresAt) {
  await getFirestore()
    .collection("users")
    .doc(uid)
    .set(
      {
        pro,
        proExpiresAt: expiresAt ? Timestamp.fromMillis(expiresAt) : null,
        proUpdatedAt: FieldValue.serverTimestamp(),
        ...(pro ? { syncWarnedAt: FieldValue.delete() } : {}),
      },
      { merge: true },
    );
  try {
    const auth = getAuth();
    const { proUntil: _, ...current } = (await auth.getUser(uid)).customClaims || {};
    await auth.setCustomUserClaims(uid, {
      ...current,
      pro,
      ...(pro && expiresAt ? { proUntil: expiresAt } : {}),
    });
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
  }
}

function timingSafeEqual(a, b) {
  const left = Buffer.from(String(a));
  const right = Buffer.from(String(b));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

/**
 * Deleting an account deletes everything kept for it: the account document
 * with its devices, synced records and sync settings, every relay key its
 * servers held, and its customer in RevenueCat. The stores keep their own
 * record of a purchase; that is theirs, not ours.
 *
 * A subscription bought on the web is cancelled at once, without a refund:
 * with the account gone, nobody could reach the billing portal to stop it.
 * A store subscription is the store's to cancel, which the app says before
 * the account is deleted. A cancellation Stripe refuses is logged as an
 * error and the rest of the cleanup still runs.
 *
 * A v1 trigger because Cloud Functions v2 has no event for a deleted user.
 */
exports.cleanupUser = functionsV1
  .region("europe-central2")
  .runWith({ secrets: [revenueCatKey, stripeKey] })
  .auth.user()
  .onDelete(async (user) => {
    const stripe = (stripeKey.value() || "").trim();
    if (stripe) {
      try {
        const cancelled = await cancelStripeSubscriptions(user.uid, stripe);
        if (cancelled.length > 0) {
          console.log(`Cancelled web subscriptions of a deleted account: ${cancelled.join(", ")}`);
        }
      } catch (error) {
        console.error(`Web subscriptions of deleted account ${user.uid} may still bill: ${error.message}`);
      }
    } else {
      console.warn("STRIPE_SECRET_KEY is unset; web subscriptions were not checked");
    }
    const db = getFirestore();
    await db.recursiveDelete(db.collection("users").doc(user.uid));
    const keys = await db.collection("relayKeys").where("uid", "==", user.uid).get();
    await Promise.all(keys.docs.map((doc) => doc.ref.delete()));
    const key = (revenueCatKey.value() || "").trim();
    if (key) {
      const response = await fetch(
        `https://api.revenuecat.com/v2/projects/${REVENUECAT_PROJECT}/customers/` +
          `${encodeURIComponent(user.uid)}`,
        { method: "DELETE", headers: { Authorization: `Bearer ${key}` } },
      );
      if (!response.ok && response.status !== 404) {
        console.warn(`RevenueCat refused to delete the customer: ${response.status}`);
      }
    }
  });

/** The account behind a Firebase ID token sent as a bearer token, or null. */
async function caller(request) {
  try {
    const header = request.get("authorization") || "";
    return (await getAuth().verifyIdToken(header.replace(/^Bearer /, ""))).uid;
  } catch (_) {
    return null;
  }
}

/**
 * Deletes an account's synced copy: its sync settings and every record. The
 * settings go first: a device checks them before every sync and stops when
 * they are gone, so none of them can put records back under the old key
 * while the records are being deleted.
 */
async function deleteSyncCopy(uid) {
  const db = getFirestore();
  const user = db.collection("users").doc(uid);
  await db.recursiveDelete(user.collection("syncMeta"));
  await db.recursiveDelete(user.collection("records"));
  await user.set({ syncWarnedAt: FieldValue.delete() }, { merge: true });
}

/**
 * Turns sync off for the whole account and deletes the synced copy: `POST`
 * with the account's ID token. Pro is not needed - deleting your own data
 * is never something you pay for. The devices notice on their next sync
 * and forget their key; their own data stays.
 */
exports.deleteSyncData = onRequest(guarded(async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).end();
    return;
  }
  const uid = await caller(request);
  if (!uid) {
    response.status(401).end();
    return;
  }
  await deleteSyncCopy(uid);
  response.status(200).json({ deleted: true });
}));

/**
 * Once a day: a synced copy outlives Pro by a year. Eleven months after Pro
 * ends the account is emailed; a month after that, with Pro still not back,
 * the copy is deleted. Without a working mailer nothing is ever deleted.
 */
exports.sweepLapsedSync = onSchedule(
  {
    schedule: "every day 04:00",
    timeZone: "Europe/Warsaw",
    secrets: [mailKey],
    timeoutSeconds: 540,
  },
  async () => {
    const db = getFirestore();
    const key = (mailKey.value() || "").trim();
    const mail = key && key !== "unset";
    const now = Date.now();
    const users = await db.collection("users").where("pro", "==", false).get();
    for (const doc of users.docs) {
      const data = doc.data();
      const meta = await doc.ref.collection("syncMeta").doc("key").get();
      if (!meta.exists) continue;
      const lapsed = data.proExpiresAt || data.proUpdatedAt;
      const action = syncSweepAction(
        {
          pro: false,
          lapsedAt: lapsed ? lapsed.toMillis() : null,
          warnedAt: data.syncWarnedAt ? data.syncWarnedAt.toMillis() : null,
        },
        now,
      );
      if (action === "warn" && mail && (await warnBeforeDeleting(doc.id, key))) {
        await doc.ref.set({ syncWarnedAt: FieldValue.serverTimestamp() }, { merge: true });
      } else if (action === "delete" && mail) {
        await deleteSyncCopy(doc.id);
      }
    }
  },
);

/** Emails the account that its synced copy goes in a month. */
async function warnBeforeDeleting(uid, key) {
  let email;
  try {
    email = (await getAuth().getUser(uid)).email;
  } catch (_) {
    return false;
  }
  if (!email) return false;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: MAIL_FROM,
      to: [email],
      subject: "Your Termphin synced copy will be deleted in 30 days",
      text:
        "Your Termphin Pro ended almost a year ago, so in 30 days we will delete " +
        "the encrypted copy your devices synced through us.\n\n" +
        "Nothing on your devices changes: your machines, keys and snippets stay " +
        "where they are. To keep the synced copy, renew Termphin Pro in the app " +
        "before then and sync picks up where it stopped.\n\n" +
        "You can also delete it yourself now, in the app under Settings, " +
        "Account, Sync.\n\n- Termphin",
    }),
  });
  return response.ok;
}

