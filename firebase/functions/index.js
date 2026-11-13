const crypto = require("node:crypto");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { setGlobalOptions } = require("firebase-functions/v2");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { proFromEvent, parseRelayKey, cleanText } = require("./lib");

initializeApp();
setGlobalOptions({ region: "europe-central2", maxInstances: 10 });

/** The `Authorization` header RevenueCat is configured to send. */
const revenueCatAuth = defineSecret("REVENUECAT_WEBHOOK_AUTH");

/** Seconds between two pushes sent with one relay key. */
const RELAY_QUIET_SECONDS = 3;

/**
 * RevenueCat's webhook: the one place Pro is granted or taken away.
 *
 * The app logs in to RevenueCat with the Firebase uid, so `app_user_id` is
 * the uid. The outcome goes to two places: `users/{uid}` for the app to
 * read, and the `pro` custom claim for the security rules and the relay -
 * a client can write neither.
 */
exports.revenuecat = onRequest(
  { secrets: [revenueCatAuth] },
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
 * connected: `POST {key, title, body}`. The key is made on the phone, which
 * stored only its hash; it names the user. Pro only.
 *
 * The text is passed through to FCM and kept nowhere.
 */
exports.relay = onRequest(async (request, response) => {
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
  const allowed = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(keyRef);
    if (!snapshot.exists) return { status: 403 };
    const data = snapshot.data();
    const hash = crypto.createHash("sha256").update(key.secret).digest("hex");
    if (!timingSafeEqual(hash, data.secretHash)) return { status: 403 };
    const last = data.lastSentAt ? data.lastSentAt.toMillis() : 0;
    if (Date.now() - last < RELAY_QUIET_SECONDS * 1000) return { status: 429 };
    tx.update(keyRef, { lastSentAt: FieldValue.serverTimestamp() });
    return { status: 200, uid: data.uid, label: data.label };
  });
  if (allowed.status !== 200) {
    response.status(allowed.status).end();
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
  const body = cleanText(request.body.body);
  const result = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { kind: "relay", label: allowed.label || "" },
    android: { priority: "high", notification: { channelId: "terminal_alerts" } },
    apns: { payload: { aps: { sound: "default" } } },
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
});

function isPro(user) {
  if (!user || user.pro !== true) return false;
  if (!user.proExpiresAt) return true;
  return user.proExpiresAt.toMillis() > Date.now();
}

async function setPro(uid, pro, expiresAt) {
  await getFirestore()
    .collection("users")
    .doc(uid)
    .set(
      {
        pro,
        proExpiresAt: expiresAt ? Timestamp.fromMillis(expiresAt) : null,
        proUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  try {
    const auth = getAuth();
    const current = (await auth.getUser(uid)).customClaims || {};
    await auth.setCustomUserClaims(uid, { ...current, pro });
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
  }
}

function timingSafeEqual(a, b) {
  const left = Buffer.from(String(a));
  const right = Buffer.from(String(b));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}
