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
import '../settings/terminal_settings.dart';
import '../ssh/remote_agent_service.dart'
    show powerShellCommandLine, shellQuote;
import '../ssh/ssh_session_manager.dart';
import '../terminal/in_app_alerts.dart';
import 'machine_shell.dart';
import 'machine_switches.dart';
import 'notify_prefs_store.dart';
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
const _registeredUidPrefsKey = 'push_registered_uid';
const _serverKeysPrefsKey = 'push_server_keys';
const _pendingMachinesPrefsKey = 'pending_machines';
const _agentHooksPrefsKey = 'push_agent_hooks';

/// The payload prefix of a push shown while the app is open: what follows
/// is `<profileId>:<session>`.
const kRelayPayloadPrefix = 'relay:';

/// What push registration does when the signed-in account may have
/// changed: at launch and whenever another account (or none) signs in.
enum PushAccountStep {
  /// Nothing is registered anywhere, or push is off.
  nothing(rotates: false, registers: false),

  /// The token is already the signed-in account's: written again, as every
  /// launch does, so a token refreshed meanwhile is current.
  register(rotates: false, registers: true),

  /// Nothing was registered: the signed-in account gets this device.
  registerFresh(rotates: false, registers: true),

  /// Another account had this device, or nobody knows which did: the token
  /// is thrown away first, so the other account's entry is left with a
  /// token FCM refuses - which the relay deletes - and its pushes stop.
  rotateAndRegister(rotates: true, registers: true),

  /// Signed out: the token is thrown away, so no account reaches this
  /// device until one signs in again.
  rotate(rotates: true, registers: false);

  const PushAccountStep({required this.rotates, required this.registers});

  final bool rotates;
  final bool registers;
}

/// Decides [PushAccountStep] from [registeredUid] - the account this
/// device's token was last registered under: empty for none, null for an
/// install from before that was remembered - and [currentUid], the account
/// signed in now. An FCM token belongs to the install, not the account, so
/// without the rotation a token registered under one account keeps that
/// account's pushes coming after another signs in.
PushAccountStep pushAccountStep({
  required bool enabled,
  required String? registeredUid,
  required String? currentUid,
}) {
  if (!enabled) return PushAccountStep.nothing;
  final registeredNowhere = registeredUid != null && registeredUid.isEmpty;
  if (currentUid == null) {
    return registeredNowhere ? PushAccountStep.nothing : PushAccountStep.rotate;
  }
  if (registeredUid == currentUid) return PushAccountStep.register;
  if (registeredNowhere) return PushAccountStep.registerFresh;
  return PushAccountStep.rotateAndRegister;
}

/// Push notifications from servers, a Pro feature.
///
/// Two halves. This phone registers its FCM token under the account
/// (`users/{uid}/devices/{installId}`), so the relay knows where to send.
/// Each server gets a relay key - made here, its secret kept only on the
/// server, its hash in `relayKeys/{id}` - written to
/// `~/.config/termphin/relay`, and the agent sends through the relay what a
/// program asks the terminal to announce whenever no phone is attached.
///
/// Which device hears from which machine is the relay's to decide, at once:
/// each phone or tablet has its own settings in `users/{uid}/notifyPrefs`
/// ([NotifyPrefsStore]) - switched on or off - that any of the account's
/// devices, a computer too, can change; and nothing goes out from a machine
/// whose key has notifications switched off ([setMachine]).
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

  /// Whether account changes are followed yet: once, for the whole run.
  bool _followsAccounts = false;

  /// The account steps run one after another, so a sign-out followed at once
  /// by a sign-in cannot register the new account before the old token is
  /// thrown away.
  Future<void> _accountWork = Future.value();

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

  late final NotifyPrefsStore _prefs = _usesRest
      ? RestNotifyPrefsStore()
      : FirestoreNotifyPrefsStore();

  /// What this device is in the account's list of devices, set by
  /// `main.dart` from the screen: a phone until told otherwise.
  NotifyDeviceKind Function() deviceKind = () => NotifyDeviceKind.phone;

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
    await _loadPendingMachines();
    unawaited(settleOldLiveSwitches());
    enabledNotifier.value = await enabled;
    if (!_followsAccounts) {
      _followsAccounts = true;
      AccountService.instance.changes
          .map((user) => user?.uid)
          .distinct()
          .listen((uid) => unawaited(_followAccount(uid)));
    }
    await _followAccount(AccountService.instance.user?.uid);
    if (!enabledNotifier.value || AccountService.instance.user == null) return;
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openFrom(initial.data);
    } catch (_) {}
  }

  /// Moves this device's registration to the account signed in now
  /// ([pushAccountStep]). Quiet on failure: the next launch tries again.
  Future<void> _followAccount(String? uid) {
    return _accountWork = _accountWork.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        final step = pushAccountStep(
          enabled: await enabled,
          registeredUid: preferences.getString(_registeredUidPrefsKey),
          currentUid: uid,
        );
        if (step == PushAccountStep.nothing) return;
        if (!await FirebaseService.instance.start()) return;
        if (step.rotates) {
          await _forgetToken();
          await preferences.setString(_registeredUidPrefsKey, '');
        }
        if (step.registers) await _register();
      } catch (_) {}
    });
  }

  /// Throws this install's FCM token away. The refresh listener goes first:
  /// it would write the new token under the account it was made for.
  Future<void> _forgetToken() async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    // ignore: deprecated_member_use
    await FirebaseMessaging.instance.deleteToken();
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
    await _setOwnEnabled(true);
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
    await (await SharedPreferences.getInstance()).setString(
      _registeredUidPrefsKey,
      '',
    );
  }

  Future<void> _register() async {
    if (!await FirebaseService.instance.start()) return;
    final uid = AccountService.instance.user?.uid;
    if (uid == null) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    // ignore: deprecated_member_use
    final token = await messaging.getToken();
    if (token != null) {
      await _store(uid, token);
      await (await SharedPreferences.getInstance()).setString(
        _registeredUidPrefsKey,
        uid,
      );
    }
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
    final id = await _installId();
    await _devices(uid).doc(id).set({
      'token': token,
      'platform': isIOSPlatform ? 'ios' : 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await _prefs.describe(uid, id, deviceKind());
    } catch (_) {}
  }

  /// Switches this device's own entry on or off for every machine: what
  /// turning push on here means once the device is registered, and what
  /// another device's switch for it changes too. Quiet on failure.
  Future<void> _setOwnEnabled(bool enabled) async {
    final uid = AccountService.instance.user?.uid;
    if (uid == null) return;
    try {
      await _prefs.setEnabled(
        uid,
        NotifyDestination(
          id: await _installId(),
          platform: isIOSPlatform ? 'ios' : 'android',
        ),
        enabled,
      );
    } catch (_) {}
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

  /// Brings the server behind [sessionId] in line with [profile]'s switches,
  /// over that session's connection ([setUpMachine]).
  Future<void> ensureOnServer({
    required SshSessionManager manager,
    required String sessionId,
    required SshProfile profile,
  }) => setUpMachine(profile, MachineShell.session(manager, sessionId));

  /// Switches flipped on this device that have not reached their machine
  /// yet, by profile id: the next connect to it - or the quick one
  /// [setMachine] makes - finishes them. Kept across launches.
  final pendingMachines = ValueNotifier<Map<String, MachineSwitchChange>>({});

  Future<void> _loadPendingMachines() async {
    final stored = (await SharedPreferences.getInstance()).getString(
      _pendingMachinesPrefsKey,
    );
    try {
      final decoded = stored == null ? null : jsonDecode(stored);
      pendingMachines.value = {
        if (decoded is Map)
          for (final MapEntry(:key, :value) in decoded.entries)
            if (key is String) key: ?MachineSwitchChange.fromJson(value),
      };
    } on FormatException {
      pendingMachines.value = {};
    }
  }

  Future<void> _savePendingMachines(
    Map<String, MachineSwitchChange> pending,
  ) async {
    pendingMachines.value = pending;
    await (await SharedPreferences.getInstance()).setString(
      _pendingMachinesPrefsKey,
      jsonEncode({
        for (final MapEntry(:key, :value) in pending.entries)
          key: value.toJson(),
      }),
    );
  }

  /// Switches what [profile]'s machine may do, as the user asked from its
  /// card - only the switches in [change], so flipping one never decides the
  /// other: at once on the account - its key's switches; a key with both off
  /// stays until the server is cleaned up, so the machine's agent is not
  /// refused meanwhile - and then on the server, over a quick connection
  /// that asks the user nothing and gives up after [connectWithin]. True
  /// when the server was set up now; false when it could not be reached -
  /// a host key not trusted yet, a password to type, the machine off - and
  /// its next connect finishes it.
  Future<bool> setMachine(
    SshProfile profile,
    MachineSwitchChange change, {
    required SshSessionManager manager,
    Duration connectWithin = const Duration(seconds: 8),
  }) async {
    final earlier = pendingMachines.value[profile.id];
    await _savePendingMachines({
      ...pendingMachines.value,
      profile.id: earlier?.then(change) ?? change,
    });
    _checks.forget(profile.id);
    final uid = AccountService.instance.user?.uid;
    if (uid != null && await _accountReady()) {
      try {
        for (final key in await _accountKeys(uid)) {
          if (key.profileId != profile.id) continue;
          await _keys.setSwitches(
            key.keyId,
            notify: change.notify,
            live: change.live,
          );
        }
      } catch (_) {}
    }
    await _checks.idle(profile.id);
    _checks.forget(profile.id);
    try {
      final outcome = await manager.withQuietClient(
        profile,
        (client) => setUpMachine(
          profile,
          MachineShell('quick:${profile.id}', client.run),
          prepareAgent: () => manager.ensureAgentQuietly(profile, client),
        ),
        connectWithin: connectWithin,
      );
      return outcome == MachineCheck.settled;
    } catch (_) {
      return false;
    }
  }

  /// The account's keys as the server has them now, never a cached copy:
  /// taking a machine's setup away must not rest on a stale or empty one.
  Future<List<RelayServer>> _accountKeys(String uid) =>
      _keys.current(uid).timeout(const Duration(seconds: 20));

  /// Brings the machine [shell] runs on in line with what it should do
  /// ([machineSwitchesFor]): a switch flipped here and not on the server
  /// yet, or the switches on its key. A machine with nothing switched on -
  /// every machine until the user turns something on from its card - is
  /// left alone, or, when it was set up before, has it all taken away.
  /// Switched on, with Pro, it gets a relay key naming the machine and
  /// carrying the switches (made fresh when it has none, one this device did
  /// not give it, or one from before keys named it); with live status on also
  /// its presence key, the crontab lines and - through [prepareAgent], when
  /// given - the agent, so it shows before its first session.
  /// A key made for another machine pointing at the same server is never
  /// taken over, switched or deleted for this one ([keyBelongsTo],
  /// [adoptableKey], [mayClearServer]): each writes its own key there when
  /// it connects, and the server reports as whichever did last.
  /// Quiet on every failure. Only a machine that ended up as it should counts
  /// as checked: one met signed out or before Pro was confirmed is looked at
  /// again on the next chance instead of waiting for a restart.
  ///
  /// Returns how it went; [MachineCheck.settled] at once for a machine
  /// already settled since launch, and null for one being checked right now
  /// or waiting after a failure.
  Future<MachineCheck?> setUpMachine(
    SshProfile profile,
    MachineShell shell, {
    Future<void> Function()? prepareAgent,
  }) async {
    if (_checks.isSettled(profile.id)) return MachineCheck.settled;
    final run = _checks.start(profile.id);
    if (run == null) return null;
    shell = _checks.guard(run, shell);
    var outcome = MachineCheck.notReady;
    MachineSwitches? applied;
    try {
      final remembered = (await _serverKeys())[profile.id];
      final pending = pendingMachines.value[profile.id];
      final uid = AccountService.instance.user?.uid;
      if (uid == null || !await _accountReady()) return outcome;
      final keys = await _accountKeys(uid);
      final given =
          remembered != null && keyBelongsTo(remembered, profile.id, keys)
          ? remembered
          : null;
      if (remembered != null && given == null) {
        await _dropRemembered(profile.id);
      }
      final own = keys.where((key) => key.profileId == profile.id).firstOrNull;
      final wanted = await resolveMachineSwitches(
        change: pending,
        key: own,
        legacyKey: isLegacyServerKey(given, keys),
        hadNotifications: () =>
            _hadNotifications(shell, fallback: profile.serverNotifications),
        hadLiveStatus: () => _hadLiveStatus(shell, profile.id),
      );
      applied = wanted;
      if (!wanted.any) {
        if (given != null || pending != null || own != null) {
          final windows = await _onWindows(shell);
          final onServer = await _keyOnServer(shell, windows: windows);
          final ownIds = [
            ?given,
            for (final key in keysOfMachine(keys, profile.id)) key.keyId,
          ];
          if (mayClearServer(onServer, ownIds)) {
            await shell.exec(
              windows ? relayRemoveCommandWindows() : relayRemoveCommand,
            );
            await _removePresence(shell);
          }
          await _removeAgentHooks(shell, profile.id, windows: windows);
          if (given != null) {
            try {
              await _forget(profile.id, given);
            } catch (_) {}
          }
          for (final key in keys) {
            if (key.profileId != profile.id || key.keyId == given) continue;
            try {
              await _deleteKey(key.keyId);
            } catch (_) {}
          }
        }
        outcome = MachineCheck.settled;
        return outcome;
      }
      if (!ProService.instance.confirmed.value && !_proRefreshed) {
        _proRefreshed = true;
        await ProService.instance.refresh();
      }
      if (!ProService.instance.confirmed.value) return outcome;
      final named = {
        for (final key in keys)
          if (key.profileId != null) key.keyId,
      };
      final windows = await _onWindows(shell);
      Future<void> unquiet() => shell.exec(
        windows
            ? relayQuietCommandWindows(quiet: false)
            : relayQuietCommand(quiet: false),
      );
      String? kept;
      final onServer = await _keyOnServer(shell, windows: windows);
      if (given != null && named.contains(given)) {
        if (keyIdAnswered(onServer, given)) kept = given;
      }
      String? adopted;
      if (kept == null && given == null) {
        adopted = adoptableKey(onServer, profile.id, keys);
        if (adopted != null && named.contains(adopted)) {
          kept = adopted;
          await _rememberKey(profile.id, adopted);
        }
      }
      if (kept != null) {
        await unquiet();
        await _keys.setSwitches(kept, notify: wanted.notify, live: wanted.live);
      } else {
        final keyId = await installOnServer(
          shell: shell,
          label: profile.name,
          profileId: profile.id,
          notify: wanted.notify,
          live: wanted.live,
        );
        if (given != null) await _deleteKey(given);
        if (adopted != null) await _deleteKey(adopted);
        await _rememberKey(profile.id, keyId);
        unawaited(
          AnalyticsService.instance.capture(AnalyticsEvent.relayServerAdded),
        );
      }
      if (wanted.live) {
        if (prepareAgent != null) {
          try {
            await prepareAgent();
          } catch (_) {}
        }
        await _ensurePresenceKey(shell, profile.id);
      } else {
        await _removePresence(shell);
      }
      await _removeAgentHooks(shell, profile.id, windows: windows);
      outcome = MachineCheck.settled;
    } catch (_) {
      outcome = MachineCheck.failed;
      unawaited(
        AnalyticsService.instance.capture(AnalyticsEvent.relayServerFailed),
      );
    } finally {
      _checks.finish(run, outcome);
      if (outcome == MachineCheck.settled &&
          pendingSettledBy(pendingMachines.value[profile.id], applied)) {
        await _savePendingMachines(
          {...pendingMachines.value}..remove(profile.id),
        );
      }
    }
    return outcome;
  }

  /// Takes Termphin's hooks out of Claude Code and Codex on the machine
  /// behind [shell] when an earlier build of this app put them there. The
  /// app no longer writes into other programs' settings; a hook that is
  /// wanted is set up by hand (`termphin-agent hooks install`), and one set
  /// up that way is left alone. Quiet on failure: tried again next time.
  Future<void> _removeAgentHooks(
    MachineShell shell,
    String profileId, {
    required bool windows,
  }) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final installed = {...?preferences.getStringList(_agentHooksPrefsKey)};
      if (!installed.contains(profileId)) return;
      final output = utf8.decode(
        await shell.exec(
          windows
              ? agentHooksCommandWindows(install: false)
              : agentHooksCommand(install: false),
        ),
        allowMalformed: true,
      );
      if (!agentHooksAnswered(output, install: false)) return;
      installed.remove(profileId);
      await preferences.setStringList(_agentHooksPrefsKey, installed.toList());
    } catch (_) {}
  }

  /// Whether the machine behind [shell] had notifications before keys
  /// carried the switch: its relay file is not quiet. [fallback] - the
  /// machine's own setting from before the bell - when it has no relay file.
  Future<bool> _hadNotifications(
    MachineShell shell, {
    required bool fallback,
  }) async {
    final windows = await _onWindows(shell);
    return hadNotificationsFrom(
      utf8.decode(
        await shell.exec(
          windows ? relayLoudnessCommandWindows() : relayLoudnessCommand,
        ),
        allowMalformed: true,
      ),
      fallback: fallback,
    );
  }

  /// Whether the machine behind [shell] was set up for live status before
  /// keys carried the switch ([hadLiveStatus]).
  Future<bool> _hadLiveStatus(MachineShell shell, String profileId) =>
      hadLiveStatus(
        heldHere: () async => await presenceKeys.keyFor(profileId) != null,
        askServer: () async {
          final windows = await _onWindows(shell);
          return utf8.decode(
            await shell.exec(
              windows ? presenceExistsCommandWindows() : presenceExistsCommand,
            ),
            allowMalformed: true,
          );
        },
      );

  /// Writes `live: true` on the account's keys from before the switch
  /// existed whose machine this device holds a presence key for: they had
  /// live status, and say so now without waiting for their next connect.
  /// The rest are settled on their next connect ([setUpMachine]). Quiet on
  /// failure.
  Future<void> settleOldLiveSwitches() async {
    final uid = AccountService.instance.user?.uid;
    if (uid == null || !await _accountReady()) return;
    try {
      for (final key in await _accountKeys(uid)) {
        final profileId = key.profileId;
        if (key.live != null || profileId == null) continue;
        if (await presenceKeys.keyFor(profileId) == null) continue;
        await _keys.setSwitches(key.keyId, live: true);
      }
    } catch (_) {}
  }

  /// Takes live status off the machine behind [shell]: its presence key
  /// and, on a POSIX server, the crontab lines. Quiet on failure.
  Future<void> _removePresence(MachineShell shell) async {
    try {
      final windows = await _onWindows(shell);
      await shell.exec(
        windows ? presenceRemoveCommandWindows() : presenceRemoveCommand,
      );
      if (!windows) await shell.exec(presenceCronRemoveCommand());
    } catch (_) {}
  }

  /// Gives the machine behind [shell] a presence key when it has none and
  /// keeps whichever key it holds on this device, so this device can read the
  /// sessions its agent reports; on a POSIX server also puts the crontab
  /// lines in place that keep it online while it has no session. Quiet on failure: live presence is a bonus
  /// on top of the relay, never a reason to call the machine failed.
  Future<void> _ensurePresenceKey(MachineShell shell, String profileId) async {
    try {
      final windows = await _onWindows(shell);
      final fresh = encodePresenceKey(newPresenceKey());
      final output = utf8.decode(
        await shell.exec(
          windows
              ? presenceKeyCommandWindows(kPresenceUrl, fresh)
              : presenceKeyCommand(kPresenceUrl, fresh),
        ),
        allowMalformed: true,
      );
      final key = parsePresenceKey(output);
      if (key != null) await presenceKeys.remember(profileId, key);
      if (!windows) {
        await shell.exec(presenceCronInstallCommand());
        await shell.exec(presenceReportNowCommand());
      }
    } catch (_) {}
  }

  /// Makes a relay key for the machine behind [shell] and writes it
  /// there, readable by its user alone. [label] names the server in the
  /// list of keys and in pushes without a title. Returns the key's id.
  ///
  /// The key is registered with the relay only once the server shows it
  /// back: a command that failed there - a restricted shell, a full disk -
  /// leaves nothing behind, where registering first left a key in the
  /// account for every failed try.
  Future<String> installOnServer({
    required MachineShell shell,
    required String label,
    String? profileId,
    bool quiet = false,
    bool notify = true,
    bool live = false,
  }) async {
    final uid = AccountService.instance.user?.uid;
    if (uid == null || !await _accountReady()) {
      throw StateError('Not signed in.');
    }
    final key = newRelayKey();
    final windows = await _onWindows(shell);
    await shell.exec(
      windows
          ? relayInstallCommandWindows(kRelayUrl, key.token, quiet: quiet)
          : relayInstallCommand(kRelayUrl, key.token, quiet: quiet),
    );
    final written = utf8.decode(
      await shell.exec(
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
      notify: notify,
      live: live,
    );
    return key.id;
  }

  /// Whether the machine behind [shell] is Windows. `uname -s` is asked
  /// because it answers on every POSIX server and fails on cmd.exe and
  /// PowerShell alike, which is what decides the command shape.
  Future<bool> _onWindows(MachineShell shell) async {
    final cached = _windowsBySession[shell.key];
    if (cached != null) return cached;
    final output = utf8.decode(
      await shell.exec('uname -s'),
      allowMalformed: true,
    );
    final windows = unameSaysWindows(output)
        ? true
        : unameSaysPosix(output)
        ? false
        : throw StateError('Could not tell the server system from: $output');
    _windowsBySession[shell.key] = windows;
    return windows;
  }

  /// The account's phones and tablets with their notification settings,
  /// latest registration first.
  Stream<List<NotifyDestination>> destinations() {
    final uid = AccountService.instance.user?.uid;
    if (uid == null) return Stream.value(const []);
    return Stream.fromFuture(_accountReady()).asyncExpand(
      (ready) => ready
          ? _prefs.list(uid)
          : const Stream<List<NotifyDestination>>.empty(),
    );
  }

  /// Switches [destination] on or off for every machine, at once: the relay
  /// reads it on every push.
  Future<void> setDestinationEnabled(
    NotifyDestination destination,
    bool enabled,
  ) async {
    final uid = AccountService.instance.user?.uid;
    if (uid == null) return;
    await _prefs.setEnabled(uid, destination, enabled);
  }

  /// Gives [destination] its own [name], or takes it away with null.
  Future<void> setDestinationName(
    NotifyDestination destination,
    String? name,
  ) async {
    final uid = AccountService.instance.user?.uid;
    if (uid == null) return;
    await _prefs.setName(uid, destination, name);
  }

  /// The servers holding a key to this account, newest first.
  Stream<List<RelayServer>> servers() {
    final uid = AccountService.instance.user?.uid;
    if (uid == null) return Stream.value(const []);
    return Stream.fromFuture(_accountReady()).asyncExpand(
      (ready) =>
          ready ? _keys.list(uid) : const Stream<List<RelayServer>>.empty(),
    );
  }

  /// What the relay key id command prints on the machine behind [shell]:
  /// the id of the key its relay file holds, if any.
  Future<String> _keyOnServer(
    MachineShell shell, {
    required bool windows,
  }) async => utf8.decode(
    await shell.exec(windows ? relayKeyIdCommandWindows() : relayKeyIdCommand),
    allowMalformed: true,
  );

  /// Forgets the machine of [profileId], deleted by the user: its keys go
  /// from the account - so the relay and the realtime backend take nothing
  /// more from them, and no other device lists them - along with what this
  /// device remembered for it. The server is not touched: another machine
  /// may point at the same one, and its next connect replaces the file.
  /// Quiet on failure.
  Future<void> forgetMachine(String profileId) async {
    _checks.forget(profileId);
    if (pendingMachines.value.containsKey(profileId)) {
      await _savePendingMachines({...pendingMachines.value}..remove(profileId));
    }
    final remembered = await _serverKeys();
    final given = remembered.remove(profileId);
    if (given != null) await _saveServerKeys(remembered);
    final uid = AccountService.instance.user?.uid;
    if (uid == null || !await _accountReady()) return;
    try {
      final keys = await _accountKeys(uid);
      for (final key in keysOfMachine(keys, profileId)) {
        await _deleteKey(key.keyId);
      }
      if (given != null && keyBelongsTo(given, profileId, keys)) {
        await _deleteKey(given);
      }
    } catch (_) {}
  }

  Future<void> _forget(String profileId, String keyId) async {
    await _deleteKey(keyId);
    await _dropRemembered(profileId);
  }

  /// Forgets which key this device gave the machine of [profileId], leaving
  /// the key itself alone.
  Future<void> _dropRemembered(String profileId) async {
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
/// Runs the agent's `hooks install` - or `hooks remove` - on a POSIX server
/// when the agent is there: Termphin's hooks into Claude Code's and Codex's
/// own settings, everything else in them left as it was.
String agentHooksCommand({required bool install}) =>
    'sh -c ${shellQuote('bin="\$HOME/.local/lib/termphin/termphin-agent"; [ -x "\$bin" ] && "\$bin" hooks ${install ? 'install' : 'remove'} 2>/dev/null || true')}';

/// The Windows twin of [agentHooksCommand], as a PowerShell script run
/// through [powerShellCommandLine]: the agent sits under the user's
/// `AppData\Local\termphin\bin` there.
String agentHooksCommandWindows({required bool install}) =>
    powerShellCommandLine('''
\$ProgressPreference = 'SilentlyContinue'
\$bin = Join-Path \$env:USERPROFILE 'AppData\\Local\\termphin\\bin\\termphin-agent.exe'
if (Test-Path -LiteralPath \$bin) { & \$bin hooks ${install ? 'install' : 'remove'} 2>\$null }
''');

/// Whether the agent's answer to [agentHooksCommand] says it did its job:
/// one of the agents got the hooks, or had them taken out. An agent too old
/// to know `hooks`, or a server without one, says neither.
bool agentHooksAnswered(String output, {required bool install}) {
  final lines = output.split('\n').map((line) => line.trim());
  return install
      ? lines.any(
          (line) => line == 'claude installed' || line == 'codex installed',
        )
      : lines.any(
          (line) => line == 'claude removed' || line == 'codex removed',
        );
}

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

/// Prints `present` when the server holds a presence key, and changes
/// nothing.
@visibleForTesting
const presenceExistsCommand =
    '[ -s ~/.config/termphin/presence ] && echo present || true';

/// Prints the id half of the server's relay key and nothing of its secret,
/// or [kNoRelayFile] when there is no relay file. Run through `sh`, since
/// the login shell it reaches may be fish or tcsh, which speak no `if`.
@visibleForTesting
final relayKeyIdCommand =
    'sh -c ${shellQuote("if [ -e ~/.config/termphin/relay ] || [ -L ~/.config/termphin/relay ]; "
    "then cut -d' ' -f2 ~/.config/termphin/relay 2>/dev/null | cut -d. -f1; "
    "else echo $kNoRelayFile; fi")}';

/// What the key id command prints, on a line of its own, when the server
/// has no relay file at all - the one answer that says "no key" for sure,
/// where an empty one may be a file that could not be read.
@visibleForTesting
const kNoRelayFile = 'termphin-no-relay-file';

/// Prints how the server's relay file stands: `quiet` when its pushes are
/// held back, `loud` when they go out, `none` when there is no file. Run
/// through `sh`, like [relayKeyIdCommand].
@visibleForTesting
final relayLoudnessCommand =
    'sh -c ${shellQuote('f=~/.config/termphin/relay; if [ ! -s "\$f" ]; then echo none; '
    'elif [ "\$(cut -d\' \' -f3 "\$f")" = quiet ]; then echo quiet; '
    'else echo loud; fi')}';

/// Whether a machine had notifications, from what [relayLoudnessCommand]
/// printed: not when its relay file is quiet; [fallback] when it has none.
/// Throws on any other answer - a file that could not be read is no answer.
@visibleForTesting
bool hadNotificationsFrom(String answer, {required bool fallback}) {
  final lines = answer.split(RegExp(r'\r?\n')).map((line) => line.trim());
  if (lines.contains('quiet')) return false;
  if (lines.contains('loud')) return true;
  if (lines.contains('none')) return fallback;
  throw StateError('Could not tell whether the relay file is quiet: $answer');
}

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
} else {
  'termphin-no-relay-file'
}
''');

/// The Windows twin of [relayLoudnessCommand].
@visibleForTesting
String relayLoudnessCommandWindows() => powerShellCommandLine(r'''
$ProgressPreference = 'SilentlyContinue'
$file = Join-Path $env:USERPROFILE '.config\termphin\relay'
if (-not (Test-Path -LiteralPath $file) -or (Get-Item -LiteralPath $file).Length -eq 0) {
  'none'
} else {
  $fields = (Get-Content -LiteralPath $file -Raw).Trim() -split ' '
  if ($fields.Count -ge 3 -and $fields[2] -eq 'quiet') { 'quiet' } else { 'loud' }
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

/// The Windows twin of [presenceExistsCommand].
@visibleForTesting
String presenceExistsCommandWindows() => powerShellCommandLine(r'''
$ProgressPreference = 'SilentlyContinue'
$file = Join-Path $env:USERPROFILE '.config\termphin\presence'
if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -gt 0) { 'present' }
''');

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

/// One check of a machine, from [MachineChecks.start] to
/// [MachineChecks.finish].
final class MachineRun {
  MachineRun._(this.id) : since = clock.now();

  final String id;
  final DateTime since;
  final _done = Completer<void>();
}

/// Which machines have been set up since launch. A machine counts as done
/// only once its key ended up as it should; one met before push was on or
/// before Pro was confirmed is looked at again on the next chance, and one
/// whose server failed waits [retryAfter] first. A check still running after
/// [runLimit] - a server that stopped answering halfway - is given up on, so
/// it holds up neither the next check nor anyone waiting for it.
@visibleForTesting
class MachineChecks {
  MachineChecks({
    this.retryAfter = const Duration(minutes: 1),
    this.runLimit = const Duration(minutes: 1),
  });

  final Duration retryAfter;
  final Duration runLimit;
  final _settled = <String>{};
  final _running = <String, MachineRun>{};
  final _failedAt = <String, DateTime>{};

  /// A check of [id] to run now, or null when it should not: settled,
  /// running, waiting after a failure.
  MachineRun? start(String id) {
    if (_settled.contains(id)) return null;
    final running = _running[id];
    if (running != null) {
      if (!_givenUp(running)) return null;
      _running.remove(id);
      running._done.complete();
    }
    final failed = _failedAt[id];
    if (failed != null && clock.now().difference(failed) < retryAfter) {
      return null;
    }
    return _running[id] = MachineRun._(id);
  }

  bool _givenUp(MachineRun run) =>
      clock.now().difference(run.since) >= runLimit;

  /// Completes once no check of [id] is running, or once the one running is
  /// given up on.
  Future<void> idle(String id) {
    final run = _running[id];
    if (run == null) return Future.value();
    final left = runLimit - clock.now().difference(run.since);
    if (left <= Duration.zero) return Future.value();
    return run._done.future.timeout(left, onTimeout: () {});
  }

  /// [run] is over, as [outcome] says. Nothing for a run given up on and
  /// started again since: the newer one decides.
  void finish(MachineRun run, MachineCheck outcome) {
    if (!identical(_running[run.id], run)) return;
    _running.remove(run.id);
    run._done.complete();
    switch (outcome) {
      case MachineCheck.settled:
        _settled.add(run.id);
        _failedAt.remove(run.id);
      case MachineCheck.notReady:
        _failedAt.remove(run.id);
      case MachineCheck.failed:
        _failedAt[run.id] = clock.now();
    }
  }

  /// [shell], refusing every command once [run] is given up on: a check
  /// stuck on a live session's connection, which nothing disconnects, must
  /// not go on changing the machine alongside the newer one.
  MachineShell guard(MachineRun run, MachineShell shell) =>
      MachineShell(shell.key, (command) async {
        if (!identical(_running[run.id], run) || _givenUp(run)) {
          throw StateError('The check of this machine was given up on.');
        }
        return shell.exec(command);
      });

  /// Whether [id] ended up as it should since launch.
  bool isSettled(String id) => _settled.contains(id);

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

/// Whether a check that set its machine up as [applied] finishes the switch
/// waiting for it ([pending]): only when the two match. One flipped again
/// while the check ran is newer than what it applied, and waits for the
/// next one.
@visibleForTesting
bool pendingSettledBy(MachineSwitchChange? pending, MachineSwitches? applied) =>
    pending != null &&
    applied != null &&
    (pending.notify == null || pending.notify == applied.notify) &&
    (pending.live == null || pending.live == applied.live);

/// The keys among [keys] made for the machine of [profileId].
@visibleForTesting
Iterable<RelayServer> keysOfMachine(
  Iterable<RelayServer> keys,
  String profileId,
) => keys.where((key) => key.profileId == profileId);

/// Whether the key [keyId] may be changed or deleted for the machine of
/// [profileId]: it names that machine, names none (a key from before keys
/// named their machine), or is gone from the account. A key naming another
/// machine - two machines pointing at one server, which earlier versions let
/// share a key - stays that machine's, so switching or deleting this one
/// never touches it.
@visibleForTesting
bool keyBelongsTo(String keyId, String profileId, Iterable<RelayServer> keys) {
  final key = keys.where((key) => key.keyId == keyId).firstOrNull;
  return key == null || key.profileId == null || key.profileId == profileId;
}

/// The account key the server's relay file holds ([onServer], what the key
/// id command printed) when the machine of [profileId] may take it over:
/// one made for it on another of the account's devices, or one from before
/// keys named their machine. Null for none, a key of another account, or one
/// made for another machine pointing at the same server.
@visibleForTesting
String? adoptableKey(
  String onServer,
  String profileId,
  Iterable<RelayServer> keys,
) {
  for (final key in keys) {
    if (!keyIdAnswered(onServer, key.keyId)) continue;
    return key.profileId == null || key.profileId == profileId
        ? key.keyId
        : null;
  }
  return null;
}

/// Whether the server's relay file ([onServer], what the key id command
/// printed) may be deleted, with the presence setup beside it, when the
/// machine is switched off: it holds one of the machine's own keys ([own]),
/// or there is no file ([kNoRelayFile]). Anything else - another machine's
/// key on the same server, another account's, a file that could not be
/// read and printed nothing - is left alone.
@visibleForTesting
bool mayClearServer(String onServer, Iterable<String> own) =>
    keyIdAnswered(onServer, kNoRelayFile) ||
    own.any((id) => keyIdAnswered(onServer, id));

/// Whether a machine was set up for live status before keys carried the
/// switch: this device holds its presence key ([heldHere]), or the server
/// has one ([askServer], what the presence check printed) - set up from
/// another device. What a key from before the switch gets written as, so
/// nobody loses live status by updating. Throws when either cannot be told:
/// a guess of "no" would take a working live status away for good.
@visibleForTesting
Future<bool> hadLiveStatus({
  required Future<bool> Function() heldHere,
  required Future<String> Function() askServer,
}) async {
  if (await heldHere()) return true;
  return (await askServer()).contains('present');
}
