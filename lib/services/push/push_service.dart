import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/platform_info.dart';
import '../account/account_service.dart';
import '../firebase/firebase_service.dart';
import '../platform/local_notifications_service.dart';
import '../security/aead.dart';
import '../ssh/ssh_session_manager.dart';

/// Where a server sends what it wants to announce while no phone is
/// connected: the `relay` function.
const kRelayUrl = String.fromEnvironment(
  'TERMPHIN_RELAY_URL',
  defaultValue:
      'https://europe-central2-termphin-hexeosoft.cloudfunctions.net/relay',
);

const _installIdPrefsKey = 'push_install_id';
const _enabledPrefsKey = 'push_enabled';

/// Push notifications from servers, a Pro feature.
///
/// Two halves. This phone registers its FCM token under the account
/// (`users/{uid}/devices/{installId}`), so the relay knows where to send.
/// A server gets a relay key - made here, secret kept only on the server,
/// its hash in `relayKeys/{id}` - written to `~/.config/termphin/relay`
/// over the session, and the agent sends what a program asks the terminal
/// to announce through the relay whenever no phone is attached to see it.
///
/// No token is made before the user turns this on: FCM auto-init is off in
/// the manifest and `Info.plist`.
///
/// It stays on FCM tokens, which `firebase_messaging` 17 deprecates for
/// installation-id registration: the relay sends with `firebase-admin`'s
/// token multicast, and both ends move together or not at all.
class PushService {
  PushService._();

  static final instance = PushService._();

  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<bool> get enabled async =>
      (await SharedPreferences.getInstance()).getBool(_enabledPrefsKey) ??
      false;

  /// Picks registration back up at launch on a phone that turned it on.
  Future<void> init() async {
    if (!await enabled) return;
    if (AccountService.instance.user == null) return;
    try {
      await _register();
    } catch (_) {}
  }

  /// Turns push on for this phone. False when notifications are refused.
  Future<bool> enable() async {
    if (!await FirebaseService.instance.start()) return false;
    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission();
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      return false;
    }
    await _register();
    await (await SharedPreferences.getInstance()).setBool(
      _enabledPrefsKey,
      true,
    );
    return true;
  }

  Future<void> disable() async {
    await (await SharedPreferences.getInstance()).setBool(
      _enabledPrefsKey,
      false,
    );
    await _tokenRefresh?.cancel();
    await _foreground?.cancel();
    _tokenRefresh = null;
    _foreground = null;
    if (!FirebaseService.instance.ready) return;
    final uid = AccountService.instance.user?.uid;
    if (uid != null) {
      await _devices(uid).doc(await _installId()).delete();
    }
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(false);
    // ignore: deprecated_member_use
    await messaging.deleteToken();
  }

  Future<void> _register() async {
    if (!await FirebaseService.instance.start()) return;
    final uid = AccountService.instance.user?.uid;
    if (uid == null) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    // ignore: deprecated_member_use
    final token = await messaging.getToken();
    if (token != null) await _store(uid, token);
    await _tokenRefresh?.cancel();
    // ignore: deprecated_member_use
    _tokenRefresh = messaging.onTokenRefresh.listen(
      (token) => unawaited(_store(uid, token)),
    );
    await _foreground?.cancel();
    _foreground = FirebaseMessaging.onMessage.listen(_showInForeground);
  }

  Future<void> _store(String uid, String token) async {
    await _devices(uid).doc(await _installId()).set({
      'token': token,
      'platform': isIOSPlatform ? 'ios' : 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// A push that arrives with the app open is not shown by the system; it
  /// goes through the same channel as the terminal's own notifications.
  void _showInForeground(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    unawaited(
      LocalNotificationsService.instance.showTerminalAlert(
        sessionId: 'relay:${message.data['label'] ?? ''}',
        title: notification.title ?? '',
        body: notification.body ?? '',
      ),
    );
  }

  CollectionReference<Map<String, dynamic>> _devices(String uid) =>
      _db.collection('users').doc(uid).collection('devices');

  Future<String> _installId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_installIdPrefsKey);
    if (existing != null) return existing;
    final id = base64Url.encode(randomBytes(16)).replaceAll('=', '');
    await preferences.setString(_installIdPrefsKey, id);
    return id;
  }

  /// Makes a relay key for the server behind [sessionId] and writes it
  /// there, readable by its user alone. [label] names the server in the
  /// notifications it sends and in the list of keys.
  Future<void> installOnServer({
    required SshSessionManager manager,
    required String sessionId,
    required String label,
  }) async {
    final uid = AccountService.instance.user?.uid;
    if (uid == null || !await FirebaseService.instance.start()) {
      throw StateError('Not signed in.');
    }
    final key = newRelayKey();
    await _db.collection('relayKeys').doc(key.id).set({
      'uid': uid,
      'secretHash': key.secretHash,
      'label': label.length > 100 ? label.substring(0, 100) : label,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await manager.exec(sessionId, relayInstallCommand(kRelayUrl, key.token));
  }
}

/// A relay key: the [id] its document is stored under, the [token] the
/// server sends, and the [secretHash] the relay checks it against.
typedef RelayKey = ({String id, String token, String secretHash});

RelayKey newRelayKey() {
  String part(int bytes) =>
      base64Url.encode(randomBytes(bytes)).replaceAll('=', '');
  final id = part(16);
  final secret = part(32);
  return (
    id: id,
    token: '$id.$secret',
    secretHash: sha256.convert(utf8.encode(secret)).toString(),
  );
}

/// The shell command that writes `<url> <token>` to the server's relay file,
/// created readable by its owner only. Both values are URL-safe, so single
/// quotes are all the quoting they need.
@visibleForTesting
String relayInstallCommand(String url, String token) =>
    "umask 077 && mkdir -p ~/.config/termphin && "
    "printf '%s %s\\n' '$url' '$token' > ~/.config/termphin/relay";
