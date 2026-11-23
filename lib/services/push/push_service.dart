import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/session_tab.dart';
import '../../models/ssh_profile.dart';
import '../../utils/platform_info.dart';
import '../account/account_service.dart';
import '../account/rest_account_backend.dart';
import '../analytics/analytics_service.dart';
import '../firebase/firebase_service.dart';
import '../platform/local_notifications_service.dart';
import '../pro/pro_service.dart';
import '../realtime/presence_keys.dart';
import '../security/aead.dart';
import '../settings/live_presence_setting.dart';
import '../settings/terminal_settings.dart';
import '../ssh/remote_agent_service.dart'
    show powerShellCommandLine, shellQuote;
import '../ssh/ssh_session_manager.dart';
import '../terminal/in_app_alerts.dart';
import 'relay_key_store.dart';

export 'relay_key_store.dart' show RelayServer;

/// Where a server sends what it wants to announce while no phone is
/// connected: the `relay` function.
const kRelayUrl = String.fromEnvironment(
  'TERMPHIN_RELAY_URL',
  defaultValue:
      'https://europe-central2-termphin-hexeosoft.cloudfunctions.net/relay',
);

const _installIdPrefsKey = 'push_install_id';
const _enabledPrefsKey = 'push_enabled';
const _serverKeysPrefsKey = 'push_server_keys';

/// The payload prefix of a push shown while the app is open: what follows
/// is `<profileId>:<session>`.
const kRelayPayloadPrefix = 'relay:';

/// Push notifications from servers, a Pro feature.
///
/// Two halves. This phone registers its FCM token under the account
/// (`users/{uid}/devices/{installId}`), so the relay knows where to send.
/// Each server gets a relay key - made here, its secret kept only on the
/// server, its hash in `relayKeys/{id}` - written to
/// `~/.config/termphin/relay`, and the agent sends through the relay what a
/// program asks the terminal to announce whenever no phone is attached.
///
/// Servers are not set up by hand: [ensureOnServer] runs on every connect,
/// gives a machine a key when it has none or a stale one, and takes it away
/// from a machine whose notifications were turned off. Which key this phone
/// gave which machine is remembered here, so a connect that finds the
/// server as it was left costs one short command.
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
  StreamSubscription<RemoteMessage>? _opened;

  /// Machines already set up since launch, so reconnects stay quiet.
  final _checks = MachineChecks();

  /// Whether Pro was asked about again since launch, which a machine that
  /// finds it unconfirmed does once rather than on every connect.
  bool _proRefreshed = false;

  /// Whether each session's server is Windows, asked once per session.
  final _windowsBySession = <String, bool>{};

  /// Opens the session a tapped push came from: the machine's profile id
  /// and the agent's session name, empty when the server did not say.
  void Function(String profileId, String session)? onOpenRelayed;

  /// Whether this phone has push on, kept current for the settings screen.
  final enabledNotifier = ValueNotifier<bool>(false);

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Whether this device reaches the account's documents through
  /// Firestore's REST API rather than the plugin: a computer.
  bool get _usesRest =>
      !FirebaseService.instance.available && RestAccountBackend.configured;

  late final RelayKeyStore _keys = _usesRest
      ? RestRelayKeyStore()
      : FirestoreRelayKeyStore();

  /// Whether the account's documents can be reached: the REST API needs
  /// nothing started, the plugin needs Firebase up.
  Future<bool> _accountReady() async =>
      _usesRest || await FirebaseService.instance.start();

  Future<bool> get enabled async =>
      (await SharedPreferences.getInstance()).getBool(_enabledPrefsKey) ??
      false;

  /// Picks registration back up at launch on a phone that turned it on, and
  /// opens the session behind a push that launched the app.
  Future<void> init() async {
    enabledNotifier.value = await enabled;
    if (!enabledNotifier.value) return;
    if (AccountService.instance.user == null) return;
    try {
      await _register();
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openFrom(initial.data);
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
    _checks.reset();
    enabledNotifier.value = true;
    await syncNoticePrefs();
    return true;
  }

  /// Writes which of the agent's notifications are on, and whether they quote
  /// the line, to `users/{uid}/settings/notices`: the document the relay
  /// reads to decide what to send. A program's own notifications are not
  /// affected. Quiet on every failure, and when no account is signed in.
  Future<void> syncNoticePrefs() async {
    try {
      if (!await enabled) return;
      final uid = AccountService.instance.user?.uid;
      if (uid == null || !await FirebaseService.instance.start()) return;
      await _db
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notices')
          .set({
            'finished': terminalSettings.finishedNotifications.value,
            'quiet': terminalSettings.quietNotifications.value,
            'lines': terminalSettings.noticeLines.value,
          }, SetOptions(merge: false));
    } catch (_) {}
  }

  Future<void> disable() async {
    await (await SharedPreferences.getInstance()).setBool(
      _enabledPrefsKey,
      false,
    );
    enabledNotifier.value = false;
    await _tokenRefresh?.cancel();
    await _foreground?.cancel();
    await _opened?.cancel();
    _tokenRefresh = null;
    _foreground = null;
    _opened = null;
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
    await _opened?.cancel();
    _opened = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _openFrom(message.data),
    );
  }

  Future<void> _store(String uid, String token) async {
    await _devices(uid).doc(await _installId()).set({
      'token': token,
      'platform': isIOSPlatform ? 'ios' : 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// A push that arrives with the app open is not shown by the system; it
  /// goes where the terminal's own notifications go - a card inside the app,
  /// or the same notification channel - and opening it opens the same
  /// session.
  void _showInForeground(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    final target = relayTarget(message.data);
    final alert = (
      sessionId: target == null
          ? '$kRelayPayloadPrefix:'
          : '$kRelayPayloadPrefix${target.$1}:${target.$2}',
      title: message.data['title'] as String? ?? notification.title ?? '',
      body: notification.body ?? '',
      source: target == null || target.$2.isEmpty
          ? null
          : SessionTab.displayName(target.$2),
    );
    if (InAppAlerts.instance.handle(alert)) return;
    unawaited(
      LocalNotificationsService.instance.showTerminalAlert(
        sessionId: alert.sessionId,
        title: alert.title,
        body: alert.body,
        source: alert.source,
      ),
    );
  }

  static const _delivered = MethodChannel(
    'dev.termphin.termphin/delivered_notifications',
  );

  /// Takes away what reached this phone about [session] of machine
  /// [profileId] - a push the system drew while the app was closed, or the
  /// copy shown while it was open - now that the session is on screen.
  Future<void> clearDelivered(String profileId, String session) async {
    await LocalNotificationsService.instance.cancelTerminalAlert(
      '$kRelayPayloadPrefix$profileId:$session',
    );
    try {
      if (isIOSPlatform) {
        await _delivered.invokeMethod<int>('removeRelayed', {
          'profileId': profileId,
          'session': session,
        });
      } else {
        await LocalNotificationsService.instance.cancelTagged(
          relayTag(profileId, session),
        );
      }
    } on Object catch (error) {
      debugPrint('Could not clear delivered pushes: $error');
    }
  }

  void _openFrom(Map<String, dynamic> data) {
    final target = relayTarget(data);
    if (target != null) onOpenRelayed?.call(target.$1, target.$2);
  }

  CollectionReference<Map<String, dynamic>> _devices(String uid) =>
      _db.collection('users').doc(uid).collection('devices');

  /// This install's id: random, made once, and what a device is known by in
  /// the account - for pushes, and to the agents its sessions attach to.
  Future<String> installId() => _installId();

  Future<String> _installId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_installIdPrefsKey);
    if (existing != null) return existing;
    final id = base64Url.encode(randomBytes(16)).replaceAll('=', '');
    await preferences.setString(_installIdPrefsKey, id);
    return id;
  }

  /// Brings the server behind [sessionId] in line with [profile]: a fresh
  /// relay key when it should have one and does not (or has one this phone
  /// did not give it), none when the machine's notifications are off.
  /// Quiet on every failure. Only a machine whose key ended up as it should
  /// counts as checked: one met before push was on, before the account was
  /// signed in or before Pro was confirmed - bought a moment later, say - is
  /// looked at again on the next chance instead of waiting for a restart.
  Future<void> ensureOnServer({
    required SshSessionManager manager,
    required String sessionId,
    required SshProfile profile,
  }) async {
    if (!_checks.start(profile.id)) return;
    var outcome = MachineCheck.notReady;
    try {
      final pushEnabled =
          !platformHas(PlatformFeature.receivesPush) || await enabled;
      final live = livePresenceSetting.value;
      if (!pushEnabled && !live) return;
      final push = pushEnabled && profile.serverNotifications;
      final uid = AccountService.instance.user?.uid;
      if (uid == null || !await _accountReady()) return;
      if (!ProService.instance.confirmed.value && !_proRefreshed) {
        _proRefreshed = true;
        await ProService.instance.refresh();
      }
      if (!ProService.instance.confirmed.value) return;
      final keys = await _serverKeys();
      final given = keys[profile.id];
      if (!push && !live) {
        if (given != null) {
          final windows = await _onWindows(manager, sessionId);
          await manager.exec(
            sessionId,
            windows ? relayRemoveCommandWindows() : relayRemoveCommand,
          );
          await _removePresence(manager, sessionId);
          await _forget(profile.id, given);
        }
        outcome = MachineCheck.settled;
        return;
      }
      if (given != null) {
        final windows = await _onWindows(manager, sessionId);
        final onServer = utf8.decode(
          await manager.exec(
            sessionId,
            windows ? relayKeyIdCommandWindows() : relayKeyIdCommand,
          ),
          allowMalformed: true,
        );
        if (keyIdAnswered(onServer, given)) {
          await manager.exec(
            sessionId,
            windows
                ? relayQuietCommandWindows(quiet: !push)
                : relayQuietCommand(quiet: !push),
          );
          await _syncPresence(manager, sessionId, profile.id, live: live);
          outcome = MachineCheck.settled;
          return;
        }
      }
      if (given == null) {
        final adopted = await _adoptServerKey(manager, sessionId, uid);
        if (adopted != null) {
          final windows = await _onWindows(manager, sessionId);
          await manager.exec(
            sessionId,
            windows
                ? relayQuietCommandWindows(quiet: !push)
                : relayQuietCommand(quiet: !push),
          );
          await _rememberKey(profile.id, adopted);
          await _syncPresence(manager, sessionId, profile.id, live: live);
          outcome = MachineCheck.settled;
          return;
        }
      }
      final keyId = await installOnServer(
        manager: manager,
        sessionId: sessionId,
        label: profile.name,
        profileId: profile.id,
        quiet: !push,
      );
      if (given != null) await _deleteKey(given);
      await _rememberKey(profile.id, keyId);
      await _syncPresence(manager, sessionId, profile.id, live: live);
      outcome = MachineCheck.settled;
      unawaited(
        AnalyticsService.instance.capture(AnalyticsEvent.relayServerAdded),
      );
    } catch (_) {
      outcome = MachineCheck.failed;
      unawaited(
        AnalyticsService.instance.capture(AnalyticsEvent.relayServerFailed),
      );
    } finally {
      _checks.finish(profile.id, outcome);
    }
  }

  /// Puts live status on the server behind [sessionId] in line with [live]:
  /// a presence key and the crontab lines when on, neither when off.
  Future<void> _syncPresence(
    SshSessionManager manager,
    String sessionId,
    String profileId, {
    required bool live,
  }) => live
      ? _ensurePresenceKey(manager, sessionId, profileId)
      : _removePresence(manager, sessionId);

  /// Takes live status off the server behind [sessionId]: its presence key
  /// and, on a POSIX server, the crontab lines. Quiet on failure.
  Future<void> _removePresence(
    SshSessionManager manager,
    String sessionId,
  ) async {
    try {
      final windows = await _onWindows(manager, sessionId);
      await manager.exec(
        sessionId,
        windows ? presenceRemoveCommandWindows() : presenceRemoveCommand,
      );
      if (!windows) await manager.exec(sessionId, presenceCronRemoveCommand());
    } catch (_) {}
  }

  /// Machines already set up are looked at again on their next connect -
  /// for live status being switched on or off.
  void recheckMachines() => _checks.reset();

  /// Gives the server behind [sessionId] a presence key when it has none and
  /// keeps whichever key it holds on this device, so this device can read the
  /// sessions its agent reports; on a POSIX server also puts the crontab
  /// lines in place that keep it online while it has no session. Quiet on failure: live presence is a bonus
  /// on top of the relay, never a reason to call the machine failed.
  Future<void> _ensurePresenceKey(
    SshSessionManager manager,
    String sessionId,
    String profileId,
  ) async {
    try {
      final windows = await _onWindows(manager, sessionId);
      final fresh = encodePresenceKey(newPresenceKey());
      final output = utf8.decode(
        await manager.exec(
          sessionId,
          windows
              ? presenceKeyCommandWindows(kPresenceUrl, fresh)
              : presenceKeyCommand(kPresenceUrl, fresh),
        ),
        allowMalformed: true,
      );
      final key = parsePresenceKey(output);
      if (key != null) await presenceKeys.remember(profileId, key);
      if (!windows) await manager.exec(sessionId, presenceCronInstallCommand());
    } catch (_) {}
  }

  /// Makes a relay key for the server behind [sessionId] and writes it
  /// there, readable by its user alone. [label] names the server in the
  /// list of keys and in pushes without a title. Returns the key's id.
  ///
  /// The key is registered with the relay only once the server shows it
  /// back: a command that failed there - a restricted shell, a full disk -
  /// leaves nothing behind, where registering first left a key in the
  /// account for every failed try.
  Future<String> installOnServer({
    required SshSessionManager manager,
    required String sessionId,
    required String label,
    String? profileId,
    bool quiet = false,
  }) async {
    final uid = AccountService.instance.user?.uid;
    if (uid == null || !await _accountReady()) {
      throw StateError('Not signed in.');
    }
    final key = newRelayKey();
    final windows = await _onWindows(manager, sessionId);
    await manager.exec(
      sessionId,
      windows
          ? relayInstallCommandWindows(kRelayUrl, key.token, quiet: quiet)
          : relayInstallCommand(kRelayUrl, key.token, quiet: quiet),
    );
    final written = utf8.decode(
      await manager.exec(
        sessionId,
        windows ? relayKeyIdCommandWindows() : relayKeyIdCommand,
      ),
      allowMalformed: true,
    );
    if (!keyIdAnswered(written, key.id)) {
      throw StateError('The relay key did not reach the server.');
    }
    await _keys.create(
      key.id,
      uid: uid,
      secretHash: key.secretHash,
      label: label.length > 100 ? label.substring(0, 100) : label,
      profileId: profileId,
    );
    return key.id;
  }

  /// Whether the server behind [sessionId] is Windows. `uname -s` is asked
  /// because it answers on every POSIX server and fails on cmd.exe and
  /// PowerShell alike, which is what decides the command shape.
  Future<bool> _onWindows(SshSessionManager manager, String sessionId) async {
    final cached = _windowsBySession[sessionId];
    if (cached != null) return cached;
    final output = utf8.decode(
      await manager.exec(sessionId, 'uname -s'),
      allowMalformed: true,
    );
    final windows = unameSaysWindows(output)
        ? true
        : unameSaysPosix(output)
        ? false
        : throw StateError('Could not tell the server system from: $output');
    _windowsBySession[sessionId] = windows;
    return windows;
  }

  /// The servers holding a key to this account, newest first.
  Stream<List<RelayServer>> servers() {
    final uid = AccountService.instance.user?.uid;
    if (uid == null || !(_usesRest || FirebaseService.instance.ready)) {
      return Stream.value(const []);
    }
    return _keys.list(uid);
  }

  /// The key already on the server behind [sessionId], when it is one of
  /// [uid]'s own - set up by another of the account's devices - so this
  /// device keeps it rather than writing a new one over it, which would
  /// leave the other device's key stale and the two replacing each other's
  /// on every connect. Null when the server has none or someone else's.
  Future<String?> _adoptServerKey(
    SshSessionManager manager,
    String sessionId,
    String uid,
  ) async {
    try {
      final windows = await _onWindows(manager, sessionId);
      final onServer = utf8.decode(
        await manager.exec(
          sessionId,
          windows ? relayKeyIdCommandWindows() : relayKeyIdCommand,
        ),
        allowMalformed: true,
      );
      final mine = await _keys
          .list(uid)
          .first
          .timeout(const Duration(seconds: 20));
      for (final server in mine) {
        if (keyIdAnswered(onServer, server.keyId)) return server.keyId;
      }
    } catch (_) {}
    return null;
  }

  /// Takes [server]'s key away: the relay refuses it from now on. The file
  /// left on the server is harmless, and replaced on its next connect if
  /// its notifications are still on.
  Future<void> revoke(RelayServer server) async {
    await _deleteKey(server.keyId);
    final keys = await _serverKeys();
    keys.removeWhere((_, keyId) => keyId == server.keyId);
    await _saveServerKeys(keys);
    final profileId = server.profileId;
    if (profileId != null) _checks.forget(profileId);
  }

  Future<void> _forget(String profileId, String keyId) async {
    await _deleteKey(keyId);
    final keys = await _serverKeys()
      ..remove(profileId);
    await _saveServerKeys(keys);
  }

  Future<void> _deleteKey(String keyId) async {
    try {
      await _keys.delete(keyId);
    } catch (_) {}
  }

  Future<void> _rememberKey(String profileId, String keyId) async {
    final keys = await _serverKeys();
    keys[profileId] = keyId;
    await _saveServerKeys(keys);
  }

  Future<Map<String, String>> _serverKeys() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _serverKeysPrefsKey,
    );
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveServerKeys(Map<String, String> keys) async {
    await (await SharedPreferences.getInstance()).setString(
      _serverKeysPrefsKey,
      jsonEncode(keys),
    );
  }
}

/// The machine and session a push names, from its data: `(profileId,
/// session)`, the session empty when the server did not say. Null when it
/// names no machine.
@visibleForTesting
/// The tag a relayed push about [session] of machine [profileId] carries on
/// Android, as `relayTag` in the functions' lib.js.
String relayTag(String profileId, String session) =>
    'relay:$profileId:$session';

(String, String)? relayTarget(Map<String, dynamic> data) {
  final profileId = data['profileId'];
  if (profileId is! String || profileId.isEmpty) return null;
  final session = data['session'];
  return (profileId, session is String ? session : '');
}

/// The machine and session in a foreground push's notification payload
/// (`relay:<profileId>:<session>`), or null for any other payload.
(String, String)? relayTargetFromPayload(String sessionId) {
  if (!sessionId.startsWith(kRelayPayloadPrefix)) return null;
  final rest = sessionId.substring(kRelayPayloadPrefix.length);
  final colon = rest.indexOf(':');
  if (colon <= 0) return null;
  return (rest.substring(0, colon), rest.substring(colon + 1));
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
/// created readable by its owner only, with ` quiet` after them when the
/// machine's notifications are off: the agent then keeps the key for live
/// status but sends no push. Both values are URL-safe, so single quotes are
/// all the quoting they need.
@visibleForTesting
String relayInstallCommand(String url, String token, {bool quiet = false}) =>
    "umask 077 && mkdir -p ~/.config/termphin && "
    "printf '%s %s${quiet ? ' quiet' : ''}\\n' '$url' '$token' > ~/.config/termphin/relay";

/// Sets or clears the ` quiet` mark on the relay file already there, keeping
/// its URL and key; does nothing without one. Through `sh`, so the user's
/// shell does not matter.
@visibleForTesting
String relayQuietCommand({required bool quiet}) {
  final script =
      'f="\$HOME/.config/termphin/relay"; [ -s "\$f" ] || exit 0; '
      'set -- \$(cat "\$f"); [ -n "\$2" ] || exit 0; umask 077; '
      'printf "%s %s${quiet ? ' quiet' : ''}\\n" "\$1" "\$2" > "\$f.tmp" && mv "\$f.tmp" "\$f"';
  return 'sh -c ${shellQuote(script)}';
}

/// Deletes the server's presence key.
@visibleForTesting
const presenceRemoveCommand = 'rm -f ~/.config/termphin/presence';

/// Prints the id half of the server's relay key and nothing of its secret,
/// or nothing when there is no key.
@visibleForTesting
const relayKeyIdCommand =
    "cut -d' ' -f2 ~/.config/termphin/relay 2>/dev/null | cut -d. -f1";

/// Deletes the server's relay key.
@visibleForTesting
const relayRemoveCommand = 'rm -f ~/.config/termphin/relay';

/// Whether `uname -s` output, its first line, names a POSIX system. Windows
/// answers with an error instead, so anything else counts as not POSIX.
@visibleForTesting
bool unameSaysPosix(String output) {
  const posixSystems = [
    'Linux',
    'Darwin',
    'FreeBSD',
    'OpenBSD',
    'NetBSD',
    'DragonFly',
    'SunOS',
    'AIX',
    'CYGWIN',
    'MINGW',
    'MSYS',
  ];
  final firstLine = output.split('\n').first.trim();
  return posixSystems.any((system) => firstLine.startsWith(system));
}

/// The Windows twin of [relayInstallCommand], as a PowerShell script run
/// through [powerShellCommandLine]. The file is restricted to the current
/// user with icacls, since a Windows file is not owner-only by default.
@visibleForTesting
String relayInstallCommandWindows(
  String url,
  String token, {
  bool quiet = false,
}) => powerShellCommandLine(
  r'''
$ProgressPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.config\termphin'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$file = Join-Path $dir 'relay'
Set-Content -Path $file -Value '''
  "'$url $token${quiet ? ' quiet' : ''}'"
  r''' -NoNewline -Encoding ascii
icacls $file /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
''',
);

/// The Windows twin of [relayKeyIdCommand]: prints the id half of the relay
/// key, nothing when the file is missing.
@visibleForTesting
String relayKeyIdCommandWindows() => powerShellCommandLine(r'''
$ProgressPreference = 'SilentlyContinue'
$file = Join-Path $env:USERPROFILE '.config\termphin\relay'
if (Test-Path -LiteralPath $file) {
  $fields = (Get-Content -LiteralPath $file -Raw -ErrorAction SilentlyContinue).Trim() -split ' '
  if ($fields.Count -ge 2) { $fields[1].Split('.')[0] }
}
''');

/// The Windows twin of [relayQuietCommand].
@visibleForTesting
String relayQuietCommandWindows({required bool quiet}) => powerShellCommandLine(
  r'''
$ProgressPreference = 'SilentlyContinue'
$file = Join-Path $env:USERPROFILE '.config\termphin\relay'
if (Test-Path -LiteralPath $file) {
  $fields = (Get-Content -LiteralPath $file -Raw).Trim() -split ' '
  if ($fields.Count -ge 2) {
    Set-Content -Path $file -Value "$($fields[0]) $($fields[1])'''
  '${quiet ? ' quiet' : ''}'
  r'''" -NoNewline -Encoding ascii
  }
}
''',
);

/// The Windows twin of [presenceRemoveCommand].
@visibleForTesting
String presenceRemoveCommandWindows() => powerShellCommandLine(r'''
$ProgressPreference = 'SilentlyContinue'
Remove-Item -Path (Join-Path $env:USERPROFILE '.config\termphin\presence') -Force -ErrorAction SilentlyContinue
''');

/// The Windows twin of [relayRemoveCommand].
@visibleForTesting
String relayRemoveCommandWindows() => powerShellCommandLine(r'''
$ProgressPreference = 'SilentlyContinue'
Remove-Item -Path (Join-Path $env:USERPROFILE '.config\termphin\relay') -Force -ErrorAction SilentlyContinue
''');

/// Whether [output] of a key id command names the key [id]. Read line by
/// line, because the command's output carries stderr too: PowerShell can
/// put its own progress records (`#< CLIXML ...`) around the answer, and a
/// whole-output comparison would then never match and give the machine a
/// new key on every connect.
@visibleForTesting
bool keyIdAnswered(String output, String id) =>
    id.isNotEmpty &&
    output.split(RegExp(r'\r?\n')).any((line) => line.trim() == id);

/// Whether `uname -s` output says the command does not exist the way
/// Windows says it: cmd.exe's "is not recognized as an internal or external
/// command" and PowerShell's "The term 'uname' is not recognized". Asked
/// alongside [unameSaysPosix], so an answer that is neither - an empty one
/// from a hiccup, a system neither list knows - is not taken for Windows
/// and sent PowerShell.
@visibleForTesting
bool unameSaysWindows(String output) => output.contains('is not recognized');

/// How a check of a machine ended.
enum MachineCheck {
  /// The machine has the key it should, or none when it should have none.
  settled,

  /// Not looked at: push off, signed out, Pro not confirmed yet. Costs
  /// nothing to ask again, and should be asked again as soon as any of it
  /// changes.
  notReady,

  /// Looked at and failed - the server did not take the key, a command
  /// failed. Asked again only after [MachineChecks.retryAfter], so a
  /// machine that keeps failing is not tried on every change in the app.
  failed,
}

/// Which machines have been set up since launch. A machine counts as done
/// only once its key ended up as it should; one met before push was on or
/// before Pro was confirmed is looked at again on the next chance, and one
/// whose server failed waits [retryAfter] first.
@visibleForTesting
class MachineChecks {
  MachineChecks({this.retryAfter = const Duration(minutes: 1)});

  final Duration retryAfter;
  final _settled = <String>{};
  final _running = <String>{};
  final _failedAt = <String, DateTime>{};

  /// Whether a check of [id] should run now: not settled, not running, not
  /// waiting after a failure.
  bool start(String id) {
    if (_settled.contains(id) || _running.contains(id)) return false;
    final failed = _failedAt[id];
    if (failed != null && clock.now().difference(failed) < retryAfter) {
      return false;
    }
    _running.add(id);
    return true;
  }

  /// The check of [id] is over, as [outcome] says.
  void finish(String id, MachineCheck outcome) {
    _running.remove(id);
    switch (outcome) {
      case MachineCheck.settled:
        _settled.add(id);
        _failedAt.remove(id);
      case MachineCheck.notReady:
        _failedAt.remove(id);
      case MachineCheck.failed:
        _failedAt[id] = clock.now();
    }
  }

  /// Checks [id] again on the next chance.
  void forget(String id) {
    _settled.remove(id);
    _failedAt.remove(id);
  }

  /// Checks every machine again on the next chance.
  void reset() {
    _settled.clear();
    _failedAt.clear();
  }
}
