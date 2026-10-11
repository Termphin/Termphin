import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../models/remote_agent_status.dart';
import '../../models/remote_shell.dart';
import '../../models/session_tab.dart';
import '../../models/ssh_profile.dart';
import '../settings/setting.dart';
import '../settings/terminal_settings.dart';
import '../sftp/cancel_token.dart';
import '../storage/profile_storage.dart';
import '../terminal/agent_probe_cache.dart';
import '../terminal/osc_markers.dart';
import '../terminal/remote_mux_commands.dart';
import 'remote_agent_service.dart';
import 'ssh_prompts.dart';
import 'ssh_service.dart';

/// When false, new tabs connect with a plain SSH shell and never probe or
/// install the Termphin helper (no persistence across disconnects).
const kRemoteAgentEnabledPrefsKey = 'remote_agent_enabled';

/// Whether the user asked for the helper.
final Setting<bool> remoteAgentSetting = Setting.boolean(
  kRemoteAgentEnabledPrefsKey,
  fallback: true,
);

/// Two tabs sharing the screen, first of the two on top or on the left, and
/// the share of the room the first one gets.
typedef SavedSplit = ({String first, String second, double ratio});

/// Owns SSH transports and persistent-session bookkeeping in Dart.
///
/// Keeping this layer platform-neutral lets the same terminal and SSH stack run
/// on Android and iOS. Remote shell persistence remains provided by the
/// Termphin helper on the server.
class SshSessionManager extends ChangeNotifier {
  SshSessionManager._({
    RemoteAgentService? remoteAgentService,
    SshService Function()? serviceFactory,
  }) : _remoteAgentService = remoteAgentService ?? const RemoteAgentService(),
       _serviceFactory = serviceFactory ?? SshService.new;

  @visibleForTesting
  SshSessionManager.test({
    RemoteAgentService? remoteAgentService,
    SshService Function()? serviceFactory,
  }) : _remoteAgentService = remoteAgentService ?? const RemoteAgentService(),
       _serviceFactory = serviceFactory ?? SshService.new;

  static final instance = SshSessionManager._();
  static const _uuid = Uuid();
  static const _sessionOrderKey = 'active_session_order';
  static const _lastActiveSessionKey = 'last_active_session_id';
  static const _sessionTabsKey = 'session_tabs';
  static const _sessionSplitsKey = 'session_splits';
  static const _agentStatusPrefix = 'remote_agent_status_';

  final RemoteAgentService _remoteAgentService;
  late final RemoteMuxCommands _mux = RemoteMuxCommands(_remoteAgentService);
  final SshService Function() _serviceFactory;
  final Map<String, ActiveSessionView> _sessions = {};
  final List<String> _sessionOrder = [];
  final List<SavedSplit> _splits = [];
  final Map<String, SessionTab> _tabs = {};
  final Map<String, RemoteAgentStatus> _agentStatuses = {};
  final AgentProbeCache _agentProbes = AgentProbeCache();
  final List<void Function(String runId, int exitCode)> _snippetRunListeners =
      [];

  bool _initialized = false;
  String? _lastActiveSessionId;

  /// How a connection asks the user about an unrecognised host key, and how
  /// it puts a keyboard-interactive round (2FA, PAM) in front of them.
  ///
  /// Installed from `main.dart` rather than imported here, for the same
  /// reason the foreground service is: both answers are drawn by Flutter, and
  /// this layer stays platform-neutral. Left null - in tests, and in any path
  /// that runs before the UI exists - an unknown host key is refused rather
  /// than waved through.
  HostKeyPrompt? hostKeyPrompt;
  KeyboardInteractivePrompt? keyboardInteractivePrompt;

  Map<String, ActiveSessionView> get sessions => Map.unmodifiable(_sessions);

  int get activeCount => _sessions.values
      .where((session) => !session.dropped && !session.isRun)
      .length;

  ActiveSessionView? getSession(String sessionId) => _sessions[sessionId];

  bool hasSession(String sessionId) => _sessions.containsKey(sessionId);

  List<ActiveSessionView> get activeSessions =>
      _ordered((session) => !session.dropped && !session.isRun);

  List<ActiveSessionView> get tabs => _ordered((session) => !session.isRun);

  List<ActiveSessionView> get snippetRunSessions =>
      _ordered((session) => session.isRun);

  /// Whether [session] belongs in the tab strip that opening a session
  /// restores around it.
  ///
  /// A tab still attached from earlier this run qualifies; so does one that
  /// was attached right up until the process died, since it is about to be
  /// picked back up. Anything the user detached on purpose does not - that
  /// lives in the new-session sheet, which is where it gets picked up from.
  ///
  /// A plain SSH tab (no termphin-agent) has nothing server-side to resume -
  /// reconnecting just opens a fresh shell, which succeeds unconditionally
  /// whether or not this is actually wanted, so it would never fail its way
  /// into being forgotten and would instead keep silently reviving itself
  /// every launch. A persistent (multiplexed) tab can at least be verified
  /// against something real on the far end, so only that kind is worth
  /// auto-reconnecting sight unseen; a dropped plain-SSH sibling waits to be
  /// picked deliberately.
  bool restorableSession(ActiveSessionView session) {
    if (!session.dropped) return true;
    if (!wasConnectedTab(session.id)) return false;
    return session.multiplexer.isPersistent;
  }

  /// Every tab a restore would pull in, across every profile.
  List<ActiveSessionView> get restorableTabs =>
      tabs.where(restorableSession).toList();

  /// How many tabs the strip ends up holding when [sessionId] is opened with
  /// every restorable sibling pulled in alongside it.
  ///
  /// This is what the session dock's badge has to promise: counting all tabs
  /// instead over-reports by however many the user detached on purpose, which
  /// are restored by nothing and so never reach the strip.
  ///
  /// The session being opened always makes the strip, restorable or not - it
  /// is the one that was asked for.
  int restoreStripSize(String sessionId) {
    final restorable = restorableTabs;
    if (restorable.any((session) => session.id == sessionId)) {
      return restorable.length;
    }
    return restorable.length + 1;
  }

  List<ActiveSessionView> _ordered(bool Function(ActiveSessionView) test) {
    final remaining = <String, ActiveSessionView>{
      for (final session in _sessions.values)
        if (test(session)) session.id: session,
    };
    final ordered = <ActiveSessionView>[];
    for (final id in _sessionOrder) {
      final session = remaining.remove(id);
      if (session != null) ordered.add(session);
    }
    final missing = remaining.values.toList()
      ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));
    return [...ordered, ...missing];
  }

  String? resumableTabIdForProfile(String profileId) =>
      resumableTabForProfile(profileId)?.tabId;

  SessionTab? resumableTabForProfile(String profileId) {
    final candidates = resumableTabsForProfile(profileId)
      ..sort((a, b) {
        if (a.detached != b.detached) return a.detached ? 1 : -1;
        return b.lastSeen.compareTo(a.lastSeen);
      });
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Every tab of [profileId] whose remote session is still on the server but
  /// has no live transport here - the tab bar only carries connected sessions,
  /// so this is what the new-session sheet offers to pick back up.
  List<SessionTab> resumableTabsForProfile(String profileId) =>
      _tabs.values.where((tab) {
        if (tab.profileId != profileId || tab.isRun) return false;
        if (!tab.multiplexer.isPersistent) return false;
        final live = _sessions[tab.tabId];
        return live == null || live.dropped;
      }).toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

  String? muxNameFor(String tabId) => _tabs[tabId]?.muxName;

  Multiplexer? multiplexerFor(String tabId) => _tabs[tabId]?.multiplexer;

  /// Whether [tabId] was actually attached the last time the app ran, per
  /// what got persisted to disk - the only signal available for a tab this
  /// process hasn't touched yet (a cold-start stub always starts `dropped`,
  /// live or not, so opening the app never auto-connects on its own).
  ///
  /// A tab the user detached on purpose never counts, however it went: the
  /// tab bar carries connected sessions only, and detaching is exactly the
  /// gesture for taking one out of it.
  bool wasConnectedTab(String tabId) {
    final tab = _tabs[tabId];
    if (tab == null) return true;
    return tab.wasConnected && !tab.detached;
  }

  /// Whether the tab strip should still be holding [tabId].
  ///
  /// False once it has been detached - deliberately parked on the server, to
  /// be picked back up from the new-session sheet - or ended outright. A tab
  /// that merely lost its connection stays true: reconnecting it is what the
  /// strip is for, which is why [restorableSession] is the wrong question
  /// here. That one asks what a *new* strip should be rebuilt from, and
  /// answers no for a dropped plain-SSH tab that the open strip must keep.
  ///
  /// A live, undropped session object wins outright: [startSession] notifies
  /// right after creating it, well before the handshake finishes and clears
  /// `detached` on the tab record, so trusting the tab record first would
  /// prune a tab that is mid-reattach. `dropped` is what [stopSession] sets
  /// on the very session it just detached, so that one still has to fall
  /// through to the tab record below.
  bool stripHoldsTab(String tabId) {
    final session = _sessions[tabId];
    if (session != null && !session.dropped) return true;
    final tab = _tabs[tabId];
    if (tab != null) return !tab.detached;
    return false;
  }

  /// Whether [tabId] has a tab record, which it only gets once a handshake
  /// has finished. [startSession] registers the session object optimistically
  /// and notifies before connecting, so a session alone says nothing about
  /// whether the connection ever happened.
  bool tabIsEstablished(String tabId) => _tabs.containsKey(tabId);

  RemoteAgentStatus? agentStatusFor(String profileId) =>
      _agentStatuses[profileId];

  ActiveSessionView? get lastActiveSession {
    final id = _lastActiveSessionId;
    if (id != null) {
      final session = _sessions[id];
      if (session != null && !session.dropped) return session;
    }
    final active = activeSessions;
    return active.isEmpty ? null : active.last;
  }

  ActiveSessionView? get lastSession {
    final id = _lastActiveSessionId;
    if (id != null) {
      final session = _sessions[id];
      if (session != null) return session;
    }
    return lastActiveSession;
  }

  List<ActiveSessionView> getSessionsForProfile(String profileId) => _sessions
      .values
      .where(
        (session) =>
            session.profile.id == profileId &&
            !session.dropped &&
            !session.isRun,
      )
      .toList();

  List<ActiveSessionView> allTabsForProfile(String profileId) {
    final live =
        _sessions.values
            .where(
              (session) =>
                  session.profile.id == profileId &&
                  !session.dropped &&
                  !session.isRun,
            )
            .toList()
          ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));
    final offline =
        _sessions.values
            .where(
              (session) =>
                  session.profile.id == profileId &&
                  session.dropped &&
                  !session.isRun,
            )
            .toList()
          ..sort((a, b) => b.connectedAt.compareTo(a.connectedAt));
    return [...live, ...offline];
  }

  void markSessionDropped(String sessionId) {
    final session = _sessions[sessionId];
    if (session != null && !session.dropped) {
      session
        ..dropped = true
        ..connecting = false;
      final tab = _tabs[sessionId];
      if (tab != null && tab.wasConnected) {
        _tabs[sessionId] = tab.copyWith(wasConnected: false);
        unawaited(_saveSessionUiState());
      }
      notifyListeners();
    }
  }

  /// Whether the app is on screen. Sessions are pinged more often while it
  /// is, so a stall shows up while someone is there to see it.
  bool _foreground = true;

  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    for (final session in _sessions.values) {
      session.sshService?.setForeground(foreground);
    }
  }

  /// Marks sessions whose transport died while the app was away.
  ///
  /// Android freezes the process in the background, so [SshService]'s
  /// keepalive timer cannot be trusted to have already noticed the drop -
  /// without this a resumed tab looks connected for up to one health-check
  /// window and eats whatever the user types. A connect still in flight has
  /// no client yet, which is not the same as a dead one - a home screen
  /// shortcut opens its session just before the activity resumes, and
  /// dropping it here would cost a reconnect on every launch.
  void dropDeadSessions() {
    for (final session in _sessions.values.toList()) {
      final service = session.sshService;
      if (!session.dropped &&
          !session.connecting &&
          service != null &&
          !service.isAlive) {
        markSessionDropped(session.id);
      }
    }
  }

  /// Asks every session the server keeps alive whether its link still
  /// answers, after a network handover or a thaw from the background - the
  /// moments a socket dies without erroring. Only those sessions: a wrong
  /// call on one costs a reconnect, on any other the shell. [handover]
  /// waits only a few round trips; see [SshService.probeConnection].
  void probeSessions({bool handover = false}) {
    for (final session in _sessions.values) {
      if (session.dropped || !session.multiplexer.isPersistent) continue;
      session.sshService?.probeConnection(quick: handover);
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadSessionUiState();
    await _restoreOfflineTabs();
    _reconcileSessionOrder();
    unawaited(_saveSessionUiState());
  }

  /// The splits the strip last left, for a restore to put back.
  List<SavedSplit> get savedSplits => [
    for (final split in _splits)
      if (_sessions.containsKey(split.first) &&
          _sessions.containsKey(split.second))
        split,
  ];

  /// Replaces what is saved about [ids] with [splits]. A strip holding only
  /// some of the tabs rewrites only those, and leaves the rest alone.
  void saveSplits(Iterable<String> ids, List<SavedSplit> splits) {
    final touched = ids.toSet();
    _splits
      ..removeWhere(
        (split) =>
            touched.contains(split.first) || touched.contains(split.second),
      )
      ..addAll(splits);
    unawaited(_saveSessionUiState());
  }

  Future<void> _loadSessionUiState() async {
    final preferences = await SharedPreferences.getInstance();
    final seen = <String>{};
    _sessionOrder
      ..clear()
      ..addAll(
        (preferences.getStringList(_sessionOrderKey) ?? const []).where(
          seen.add,
        ),
      );
    _lastActiveSessionId = preferences.getString(_lastActiveSessionKey);

    _splits.clear();
    for (final raw
        in preferences.getStringList(_sessionSplitsKey) ?? const <String>[]) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _splits.add((
          first: json['first'] as String,
          second: json['second'] as String,
          ratio: (json['ratio'] as num).toDouble(),
        ));
      } catch (error) {
        debugPrint('[SshSessionManager] Invalid split record: $error');
      }
    }

    _tabs.clear();
    for (final raw
        in preferences.getStringList(_sessionTabsKey) ?? const <String>[]) {
      try {
        final tab = SessionTab.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        _tabs[tab.tabId] = tab;
      } catch (error) {
        debugPrint('[SshSessionManager] Invalid tab record: $error');
      }
    }

    _agentStatuses.clear();
    _agentProbes.clear();
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith(_agentStatusPrefix),
    )) {
      final raw = preferences.getString(key);
      if (raw == null) continue;
      try {
        _agentStatuses[key.substring(_agentStatusPrefix.length)] =
            RemoteAgentStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (error) {
        debugPrint('[SshSessionManager] Invalid agent status: $error');
      }
    }
  }

  Future<void> _saveSessionUiState() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_sessionOrderKey, _sessionOrder);
    await preferences.setStringList(_sessionSplitsKey, [
      for (final split in _splits)
        jsonEncode({
          'first': split.first,
          'second': split.second,
          'ratio': split.ratio,
        }),
    ]);
    final lastActive = _lastActiveSessionId;
    if (lastActive == null) {
      await preferences.remove(_lastActiveSessionKey);
    } else {
      await preferences.setString(_lastActiveSessionKey, lastActive);
    }
    await _saveTabs(preferences);
  }

  Future<void> _saveTabs([SharedPreferences? preferences]) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    await prefs.setStringList(
      _sessionTabsKey,
      _tabs.values.map((tab) => jsonEncode(tab.toJson())).toList(),
    );
  }

  /// Rebuilds a dropped [ActiveSessionView] stub for every surviving tab, so
  /// a cold start can show it before anything reconnects.
  ///
  /// Detached tabs still count: [allTabsForProfile] reads [_sessions], not
  /// [_tabs], so skipping them here made an explicitly-detached session
  /// disappear from its profile's tab list, leaving only whichever one
  /// [resumableTabForProfile] happened to pick. A run's session was never
  /// persistent, so there is nothing left of it to restore beyond what it
  /// already recorded.
  Future<void> _restoreOfflineTabs() async {
    if (_tabs.isEmpty) return;
    final profiles = await ProfileStorage().loadProfiles();
    final profilesById = {for (final profile in profiles) profile.id: profile};
    var changed = false;
    for (final tab in _tabs.values.toList()) {
      final profile = profilesById[tab.profileId];
      if (profile == null) {
        _tabs.remove(tab.tabId);
        changed = true;
        continue;
      }
      if (_sessions.containsKey(tab.tabId)) continue;
      if (tab.isRun) {
        _tabs.remove(tab.tabId);
        changed = true;
        continue;
      }
      _sessions[tab.tabId] = ActiveSessionView(
        id: tab.tabId,
        profile: profile,
        connectedAt: tab.lastSeen,
        muxName: tab.muxName,
        multiplexer: tab.multiplexer,
      )..dropped = true;
      changed = true;
    }
    if (!changed) return;
    _reconcileSessionOrder();
    unawaited(_saveSessionUiState());
    notifyListeners();
  }

  void _reconcileSessionOrder({bool preserveMissingLastActive = false}) {
    final knownIds = _sessions.keys.toSet();
    _sessionOrder.removeWhere((id) => !knownIds.contains(id));
    _splits.removeWhere(
      (split) =>
          !knownIds.contains(split.first) || !knownIds.contains(split.second),
    );
    final missing =
        _sessions.values
            .where((session) => !_sessionOrder.contains(session.id))
            .toList()
          ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));
    _sessionOrder.addAll(missing.map((session) => session.id));
    if (!preserveMissingLastActive &&
        _lastActiveSessionId != null &&
        !knownIds.contains(_lastActiveSessionId)) {
      _lastActiveSessionId = null;
    }
  }

  Future<void> setActiveSession(String sessionId) async {
    if (_lastActiveSessionId == sessionId) return;
    _lastActiveSessionId = sessionId;
    await _saveSessionUiState();
  }

  void reorderSessions(List<String> sessionIds) {
    final knownIds = _sessions.keys.toSet();
    final seen = <String>{};
    final next = <String>[
      ...sessionIds.where((id) => knownIds.contains(id) && seen.add(id)),
      ..._sessionOrder.where((id) => knownIds.contains(id) && seen.add(id)),
    ];
    if (listEquals(next, _sessionOrder)) return;
    _sessionOrder
      ..clear()
      ..addAll(next);
    unawaited(_saveSessionUiState());
  }

  void addSnippetRunListener(
    void Function(String runId, int exitCode) listener,
  ) => _snippetRunListeners.add(listener);

  void removeSnippetRunListener(
    void Function(String runId, int exitCode) listener,
  ) => _snippetRunListeners.remove(listener);

  /// Opens the shell for [profile], attaching to the Termphin agent when one
  /// is enabled and the host supports it.
  ///
  /// [resume] continues a dropped session in place on the same object rather
  /// than replacing it, so the terminal showing it keeps listening; a run
  /// (`isRun`) never gets a mux name, since nothing about it is worth keeping
  /// alive on the server. The agent probe is cached per profile so a host
  /// already answered for in this process skips the extra round trip the
  /// user would otherwise watch in the connecting log; any failure to probe,
  /// install or verify the agent falls back to a plain, non-persistent shell
  /// instead of failing the connection. Output is staged until the replay
  /// handshake says whether the agent is continuing the screen in place or
  /// needs a full replay. The transport's `done` future is watched
  /// separately from `onError`, because the OS can abort a backgrounded
  /// socket in a way that would otherwise surface as an unhandled, fatal
  /// zone error rather than an ordinary disconnect. A PowerShell remote gets
  /// a throwaway resize nudge after the replay, since ConPTY buffers its
  /// first paint until a window-change reaches it and the attach client only
  /// picks up a resize sent after it has started polling its console.
  /// Latency is measured only after the replay, not before, so a reply
  /// queued behind the replay's own transfer times the transfer rather than
  /// the link. A connect failure while resuming leaves `outputPosition`
  /// alone, since it only moves once output is actually delivered - the
  /// session stays resumable on the next attempt. A classified
  /// [SshConnectException] is rethrown as itself, to keep its classification;
  /// anything else loses the doubled `Exception:` prefix a bare rethrow
  /// would otherwise leave behind.
  Future<ActiveSessionView> startSession(
    SshProfile profile, {
    String? sessionId,
    String? muxName,
    int initialWidth = 80,
    int initialHeight = 24,
    bool replayRemoteHistory = false,
    bool isRun = false,
    bool resume = false,
    void Function(String message)? onConnectionLog,
  }) async {
    final id = sessionId ?? _uuid.v4();
    final existing = _sessions[id];
    if (existing != null && !existing.dropped) return existing;
    final resuming = resume && existing != null && canResume(id);
    if (!resuming) existing?.dispose();

    final agentEnabled = remoteAgentSetting.value;
    final tab = _registerTab(
      id,
      profile,
      muxName: isRun ? '' : muxName,
      multiplexer: agentEnabled && !isRun
          ? Multiplexer.termphin
          : Multiplexer.none,
      isRun: isRun,
    );
    final service = _serviceFactory();
    final resumeFrom = resuming ? existing.outputPosition : null;
    final ActiveSessionView session;
    if (resuming) {
      session = existing;
      _retireTransport(session);
      session
        ..profile = profile
        ..sshService = service
        ..dropped = false
        ..connecting = true
        ..resumedInPlace = false;
    } else {
      session = ActiveSessionView(
        id: id,
        profile: profile,
        connectedAt: DateTime.now(),
        muxName: tab.muxName,
        multiplexer: tab.multiplexer,
        sshService: service,
        isRun: isRun,
        connecting: true,
      );
    }
    _sessions[id] = session;
    notifyListeners();

    try {
      onConnectionLog?.call(
        t.connectionLog.connectingTo(host: profile.host, port: profile.port),
      );
      await service.connect(
        profile,
        onAuthMessage: onConnectionLog,
        onConnectionLog: onConnectionLog,
        onHostKeyPrompt: hostKeyPrompt,
        onKeyboardInteractive: keyboardInteractivePrompt,
      );
      onConnectionLog?.call(t.connectionLog.authSuccessful);
      session.remoteShellType = await service.detectRemoteShell();

      var backend = tab.multiplexer;
      String? binary;
      String? agentOperatingSystem;
      String? agentVersion;
      if (tab.muxName.isEmpty) {
        backend = Multiplexer.none;
      } else if (backend == Multiplexer.termphin) {
        var probeStatus = _agentProbes.get(profile.id);
        if (probeStatus == null) {
          onConnectionLog?.call(t.connectionLog.checkingAgent);
          probeStatus = await _remoteAgentService.probe(service.client!);
        }
        if (!probeStatus.supported) {
          backend = Multiplexer.none;
        } else {
          try {
            session.agentInstalled = switch (probeStatus.publicStatus.state) {
              RemoteAgentState.missing ||
              RemoteAgentState.repair ||
              RemoteAgentState.updateAvailable => true,
              _ => false,
            };
            final agent = await _remoteAgentService.ensureForAttach(
              service.client!,
              probed: probeStatus,
            );
            binary = agent.binaryPath;
            agentOperatingSystem = agent.publicStatus.operatingSystem;
            agentVersion =
                agent.publicStatus.remoteVersion ??
                agent.publicStatus.bundledVersion;
            _agentProbes.put(profile.id, agent);
            await _recordAgentStatus(profile.id, agent.publicStatus);
          } catch (error) {
            _agentProbes.forget(profile.id);
            onConnectionLog?.call(
              t.connectionLog.agentUnavailable(error: error),
            );
            backend = Multiplexer.none;
          }
        }
      }

      final attach = backend == Multiplexer.none || binary == null
          ? null
          : _mux.attachCommand(
              backend,
              binary,
              tab.muxName,
              replayRemoteHistory,
              operatingSystem: agentOperatingSystem,
              resumeFrom: RemoteMuxCommands.agentCanResume(agentVersion)
                  ? resumeFrom
                  : null,
            );
      session
        ..multiplexer = backend
        ..muxName = attach == null ? null : tab.muxName
        ..agentBinary = attach == null || binary == null
            ? null
            : (path: binary, isWindows: agentOperatingSystem == 'Windows');

      final replayWaiter = ReplayWaiter(
        enabled: replayRemoteHistory && backend == Multiplexer.termphin,
      );
      var staging = resuming && replayWaiter.enabled;
      final staged = <Uint8List>[];
      final offsetCounter = OutputOffsetCounter();
      late final OscMarkerTracker markerTracker;
      markerTracker = OscMarkerTracker((payload) {
        offsetCounter.onOsc(payload, markerTracker.position);
        replayWaiter.onOsc(payload);
        _handleSnippetMarker(payload);
        if (payload == '5381;termphin-reboot-restored') {
          session.notifyRebootRestored();
        }
        _handleCwdMarker(session, payload);
      });
      session.serviceOutputSubscription = service.output.listen(
        (bytes) {
          replayWaiter.onOutput();
          service.quality.heard();
          markerTracker.consume(bytes);
          offsetCounter.onChunk(bytes.length);
          if (staging) {
            staged.add(bytes);
            return;
          }
          session.outputPosition = offsetCounter.position;
          session.deliverOutput(bytes);
        },
        onError: (_) => markSessionDropped(id),
      );

      onConnectionLog?.call(t.connectionLog.openingSession);
      final sshSession = await service.startShell(
        width: initialWidth,
        height: initialHeight,
        command: attach,
      );
      session.sessionDoneSubscription = sshSession.done.asStream().listen(
        (_) => markSessionDropped(id),
        onError: (_) => markSessionDropped(id),
      );
      service.onConnectionLost = () => markSessionDropped(id);
      service.startHealthCheck(
        foreground: _foreground,
        resumable: backend.isPersistent,
      );
      await replayWaiter.wait();
      if (staging) {
        staging = false;
        if (replayWaiter.resumed) {
          staged.forEach(session.deliverOutput);
          session.resumedInPlace = true;
        } else {
          session.replaceHistory(
            Uint8List.fromList([for (final chunk in staged) ...chunk]),
          );
        }
        session.outputPosition = offsetCounter.position;
        staged.clear();
      }
      service.measureLatency();
      if (session.remoteShellType == RemoteShellType.powershell) {
        final nudgedHeight = initialHeight > 1
            ? initialHeight - 1
            : initialHeight + 1;
        service.resizeTerminal(initialWidth, nudgedHeight);
        service.resizeTerminal(initialWidth, initialHeight);
      }

      _tabs[id] = tab.copyWith(
        lastSeen: DateTime.now(),
        detached: false,
        multiplexer: backend,
        wasConnected: true,
      );
      if (!_sessionOrder.contains(id)) _sessionOrder.add(id);
      await _saveSessionUiState();
      session.pendingReplay = session.rawHistorySnapshot;
      session.connecting = false;
      notifyListeners();
      onConnectionLog?.call(t.connectionLog.sessionReady);
      return session;
    } catch (error) {
      if (resuming) {
        session
          ..dropped = true
          ..connecting = false;
        _retireTransport(session);
      } else {
        _sessions.remove(id);
        session.dispose();
      }
      await service.disconnect();
      notifyListeners();
      if (error is SshConnectException) rethrow;
      throw Exception(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  SessionTab _registerTab(
    String id,
    SshProfile profile, {
    String? muxName,
    Multiplexer multiplexer = Multiplexer.termphin,
    bool isRun = false,
  }) {
    final existing = _tabs[id];
    if (existing != null && (muxName == null || existing.muxName == muxName)) {
      return existing;
    }
    return SessionTab(
      tabId: id,
      profileId: profile.id,
      muxName: muxName ?? SessionTab.generateMuxName(),
      lastSeen: DateTime.now(),
      multiplexer: multiplexer,
      isRun: isRun,
    );
  }

  /// Whether a dropped session can pick its output up where it stopped
  /// rather than replaying: the agent said where it stood, and the shell is
  /// one whose bytes arrive as the agent counted them.
  bool canResume(String sessionId) {
    final session = _sessions[sessionId];
    return session != null &&
        session.dropped &&
        !session.isDisposed &&
        !session.isRun &&
        session.outputPosition != null &&
        session.multiplexer == Multiplexer.termphin &&
        session.remoteShellType == RemoteShellType.unix;
  }

  /// Detaches a session from its transport without closing the session, so
  /// nothing the old transport still says reaches it.
  void _retireTransport(ActiveSessionView session) {
    unawaited(session.serviceOutputSubscription?.cancel());
    session.serviceOutputSubscription = null;
    unawaited(session.sessionDoneSubscription?.cancel());
    session.sessionDoneSubscription = null;
    final old = session.sshService;
    if (old == null) return;
    old
      ..onConnectionLost = null
      ..stopHealthCheck();
    unawaited(old.disconnect());
  }

  Future<void> disconnectSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    session?.dispose();
    await session?.sshService?.disconnect();
    notifyListeners();
  }

  /// Tears down the throwaway session behind a finished snippet run. Nothing
  /// of it survives on the server, so the tab record goes with it.
  Future<void> endRunSession(String sessionId) async {
    _tabs.remove(sessionId);
    _sessionOrder.remove(sessionId);
    await disconnectSession(sessionId);
    unawaited(_saveTabs());
  }

  Future<void> stopSession(
    String sessionId, {
    bool preserveOrder = false,
  }) async {
    final tab = _tabs[sessionId];
    final persistent =
        tab != null &&
        (_sessions[sessionId]?.multiplexer.isPersistent ?? false);
    if (persistent) {
      _tabs[sessionId] = tab.copyWith(lastSeen: DateTime.now(), detached: true);
    } else {
      _tabs.remove(sessionId);
    }
    await _closeTab(
      sessionId,
      preserveOrder: preserveOrder,
      forget: !persistent,
    );
  }

  /// Forgets the tab at once, then kills its session on the server.
  ///
  /// The tab goes first so nothing on screen waits on the server. The kill
  /// rides the tab's own connection, which stays open until it is done; one
  /// that does not answer within [_liveClientStallTimeout] - a link that died
  /// without the socket noticing yet - is abandoned for a fresh connection.
  /// Throws when the session could not be ended, after the tab is gone.
  Future<void> endSession(String sessionId) async {
    final session = _sessions[sessionId];
    final service = session?.sshService;
    final name = session?.muxName;
    _tabs.remove(sessionId);
    await _closeTab(
      sessionId,
      preserveOrder: false,
      forget: true,
      disconnect: false,
    );
    try {
      if (session != null && name != null) {
        await _killEnded(session, name, service?.client);
      }
    } finally {
      await service?.disconnect();
    }
  }

  Future<void> _killEnded(
    ActiveSessionView session,
    String name,
    SSHClient? client,
  ) async {
    final backend = session.multiplexer;
    if (client != null && !client.isClosed) {
      try {
        await _mux
            .kill(client, name, backend, binary: session.agentBinary)
            .timeout(_liveClientStallTimeout);
        return;
      } on TimeoutException {
        return _withTemporaryClient(
          session.profile,
          (fresh) => _killOrConfirmGone(fresh, name, backend),
        );
      }
    }
    await _withClient(
      session.profile,
      (other) => _mux.kill(other, name, backend),
    );
  }

  /// The retry after a stalled kill, which may have landed anyway. A second
  /// kill fails against a session the first one already ended, so a failure
  /// is checked against the server's own list before it counts.
  Future<void> _killOrConfirmGone(
    SSHClient client,
    String name,
    Multiplexer backend,
  ) async {
    try {
      await _mux.kill(client, name, backend);
    } catch (_) {
      final listed = await _mux.list(client);
      final stillThere =
          !listed.agent.usable ||
          listed.sessions.any((remote) => remote.name == name);
      if (stillThere) rethrow;
    }
  }

  /// Drops a tab's bookkeeping without touching the server - the escape
  /// hatch for a persistent session the app lost track of (server rebuilt,
  /// agent state wiped by an outage, ...), where [endSession] would just
  /// fail against a remote that no longer has anything to kill and leave
  /// the stale tab stuck forever.
  Future<void> forgetTab(String sessionId) async {
    _tabs.remove(sessionId);
    await _closeTab(sessionId, preserveOrder: false, forget: true);
  }

  Future<void> _closeTab(
    String sessionId, {
    required bool preserveOrder,
    required bool forget,
    bool disconnect = true,
  }) async {
    final session = _sessions[sessionId];
    if (forget) {
      _sessions.remove(sessionId);
    } else if (session != null) {
      session.dropped = true;
    }
    session?.dispose();
    try {
      if (disconnect) await session?.sshService?.disconnect();
    } finally {
      if (!preserveOrder) {
        _sessionOrder.remove(sessionId);
        if (_lastActiveSessionId == sessionId) {
          final active = activeSessions;
          _lastActiveSessionId = active.isEmpty ? null : active.last.id;
        }
      }
      await _saveSessionUiState();
      notifyListeners();
    }
  }

  /// Lists the server's sessions for [profile], pruning local tabs that have
  /// disappeared from it.
  ///
  /// Pruning only runs with a usable agent: an empty list from a host whose
  /// agent failed to probe means "could not ask", not "nothing there", and
  /// pruning on that would delete every tab over one bad connection.
  Future<List<RemoteMuxSession>> listRemoteSessions(
    SshProfile profile, {
    CancelToken? cancel,
  }) async {
    return _withClient(profile, idempotent: true, cancel: cancel, (
      client,
    ) async {
      final listed = await _mux.list(client);
      await _recordAgentStatus(profile.id, listed.agent.publicStatus);
      if (listed.agent.usable &&
          _pruneMissingRemoteTabs(profile.id, listed.sessions) > 0) {
        unawaited(_saveSessionUiState());
        notifyListeners();
      }
      return listed.sessions;
    });
  }

  /// Drops the offline tabs for [profileId] that [remote] does not account
  /// for - sessions that died with their host, leaving a tab nothing answers
  /// for. A live transport is better proof than the listing, so those stay,
  /// as do plain SSH tabs, which the list says nothing about.
  int _pruneMissingRemoteTabs(String profileId, List<RemoteMuxSession> remote) {
    final alive = {
      for (final session in remote) (session.name, session.multiplexer),
    };
    final stale = _tabs.values
        .where(
          (tab) =>
              tab.profileId == profileId &&
              tab.multiplexer.isPersistent &&
              !alive.contains((tab.muxName, tab.multiplexer)) &&
              (_sessions[tab.tabId]?.dropped ?? true),
        )
        .map((tab) => tab.tabId)
        .toList();
    for (final tabId in stale) {
      _tabs.remove(tabId);
      _sessions.remove(tabId)?.dispose();
      _sessionOrder.remove(tabId);
    }
    return stale.length;
  }

  /// Kills [name] on the server. The tabs bound to it are forgotten before
  /// the server is asked, so they leave the screen without waiting on a
  /// connection that may take seconds to open.
  Future<void> killRemoteSession(
    SshProfile profile,
    String name, {
    Multiplexer? multiplexer,
  }) async {
    final backend =
        multiplexer ?? _backendFor(profile.id, name) ?? Multiplexer.termphin;
    final bound = _tabs.values
        .where((tab) => tab.muxName == name && tab.multiplexer == backend)
        .map((tab) => tab.tabId)
        .toList();
    for (final tabId in bound) {
      _tabs.remove(tabId);
      _sessionOrder.remove(tabId);
      await disconnectSession(tabId);
    }
    if (bound.isNotEmpty) {
      unawaited(_saveSessionUiState());
      notifyListeners();
    }
    await _withClient<void>(
      profile,
      (client) => _mux.kill(client, name, backend),
    );
  }

  Future<void> renameSession(String sessionId, String newName) async {
    _mux.validateMuxName(newName);
    final session = _sessions[sessionId];
    final client = session?.sshService?.client;
    final current = session?.muxName;
    if (session == null || client == null || current == null) {
      throw Exception('Session not connected.');
    }
    await _mux.rename(client, current, newName, session.multiplexer);
    session.muxName = newName;
    final tab = _tabs[sessionId];
    if (tab != null) _tabs[sessionId] = tab.copyWith(muxName: newName);
    unawaited(_saveTabs());
    notifyListeners();
  }

  Future<void> renameRemoteSession(
    SshProfile profile,
    String oldName,
    String newName, {
    Multiplexer? multiplexer,
  }) async {
    _mux.validateMuxName(newName);
    final backend =
        multiplexer ?? _backendFor(profile.id, oldName) ?? Multiplexer.termphin;
    await _withClient<void>(
      profile,
      (client) => _mux.rename(client, oldName, newName, backend),
    );
    var changed = false;
    for (final tab
        in _tabs.values
            .where(
              (tab) => tab.muxName == oldName && tab.multiplexer == backend,
            )
            .toList()) {
      _tabs[tab.tabId] = tab.copyWith(muxName: newName);
      _sessions[tab.tabId]?.muxName = newName;
      changed = true;
    }
    if (changed) {
      unawaited(_saveTabs());
      notifyListeners();
    }
  }

  Multiplexer? _backendFor(String profileId, String muxName) {
    for (final tab in _tabs.values) {
      if (tab.profileId == profileId && tab.muxName == muxName) {
        return tab.multiplexer;
      }
    }
    return null;
  }

  Future<RemoteAgentStatus> probeAgent(SshProfile profile) async {
    final status = await _withClient(
      profile,
      idempotent: true,
      _remoteAgentService.probe,
    );
    _agentProbes.put(profile.id, status);
    await _recordAgentStatus(profile.id, status.publicStatus);
    return status.publicStatus;
  }

  /// Installs or repairs the Termphin agent on [profile].
  ///
  /// Not idempotent: a re-run would upload the binary a second time, over
  /// the copy the first attempt may still be writing.
  Future<RemoteAgentStatus> updateAgent(SshProfile profile) async {
    final status = await _withClient(
      profile,
      (client) => _remoteAgentService.install(client),
    );
    _agentProbes.put(profile.id, status);
    await _recordAgentStatus(profile.id, status.publicStatus);
    return status.publicStatus;
  }

  Future<void> _recordAgentStatus(
    String profileId,
    RemoteAgentStatus status,
  ) async {
    _agentStatuses[profileId] = status;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_agentStatusPrefix$profileId',
      jsonEncode(status.toJson()),
    );
    notifyListeners();
  }

  String adoptRemoteSession(
    SshProfile profile,
    String muxName, {
    Multiplexer multiplexer = Multiplexer.termphin,
  }) {
    final existing = _tabs.values.firstWhere(
      (tab) =>
          tab.muxName == muxName &&
          tab.profileId == profile.id &&
          tab.multiplexer == multiplexer,
      orElse: () => SessionTab(
        tabId: _uuid.v4(),
        profileId: profile.id,
        muxName: muxName,
        lastSeen: DateTime.now(),
        multiplexer: multiplexer,
      ),
    );
    _tabs[existing.tabId] = existing.copyWith(detached: false);
    if (!_sessions.containsKey(existing.tabId)) {
      _sessions[existing.tabId] = ActiveSessionView(
        id: existing.tabId,
        profile: profile,
        connectedAt: existing.lastSeen,
        muxName: existing.muxName,
        multiplexer: existing.multiplexer,
      )..dropped = true;
    }
    unawaited(_saveTabs());
    notifyListeners();
    return existing.tabId;
  }

  /// Writes [data] to [sessionId]'s transport and feeds predictive echo.
  ///
  /// A dropped session still writes - nothing is listening on the far end
  /// anyway - but skips noting the input, since keys typed into a dead
  /// transport go nowhere and should not be drawn as if they had.
  void sendInput(String sessionId, Uint8List data) {
    final session = _sessions[sessionId];
    final service = session?.sshService;
    if (session == null || service == null) return;
    service.write(data);
    if (session.dropped) return;
    session.noteInput(data);
    if (terminalSettings.predictiveEcho.value) {
      _confirmReceipt(session, service);
    }
  }

  /// Asks the server to confirm it has everything sent so far, which is how
  /// predictive echo knows the screen has caught up with the keyboard. One
  /// request out at a time: input sent meanwhile is covered by the next.
  void _confirmReceipt(ActiveSessionView session, SshService service) {
    if (session.confirmingInput) {
      session.inputAwaitingReceipt = true;
      return;
    }
    session.confirmingInput = true;
    final seq = session.inputSeq;
    unawaited(
      service
          .confirmReceipt()
          .then((_) => session.noteInputReceived(seq), onError: (_) {})
          .whenComplete(() {
            session.confirmingInput = false;
            if (session.inputAwaitingReceipt) {
              session.inputAwaitingReceipt = false;
              _confirmReceipt(session, service);
            }
          }),
    );
  }

  /// A window-change the server can act on.
  ///
  /// Nothing above here guarantees a positive size: a viewport measured while
  /// the keyboard covers the pane comes out at zero rows or fewer, and a
  /// negative int is sent as a uint32 - the server reads -1 as 4294967295
  /// rows and the remote shell dies on the next screenful of output. A
  /// terminal that small is unusable either way, so the floor costs nothing.
  void resize(String sessionId, int width, int height) {
    _sessions[sessionId]?.sshService?.resizeTerminal(
      math.max(1, width),
      math.max(1, height),
    );
  }

  Future<Uint8List> requestReplay(String sessionId) async {
    final session = _sessions[sessionId];
    final replay = session?.rawHistorySnapshot ?? Uint8List(0);
    if (session != null) session.pendingReplay = replay;
    return replay;
  }

  Future<Uint8List> exec(String sessionId, String command) async {
    final client = _sessions[sessionId]?.sshService?.client;
    if (client == null || client.isClosed) {
      throw Exception('Session not connected.');
    }
    return client.run(command);
  }

  Future<void> openTunnel(
    String sessionId,
    String ruleId,
    String ruleType,
    int localPort,
    String remoteHost,
    int remotePort, [
    String localHost = 'localhost',
  ]) async {
    final service = _sessions[sessionId]?.sshService;
    if (service == null || !service.isAlive) {
      throw Exception('Session not connected.');
    }
    if (ruleType == 'local') {
      await service.startLocalForward(
        ruleId,
        localPort,
        remoteHost,
        remotePort,
      );
    } else {
      await service.startRemoteForward(
        ruleId,
        remotePort,
        localHost,
        localPort,
      );
    }
  }

  Future<void> closeTunnel(
    String sessionId,
    String ruleId,
    String ruleType,
  ) async {
    final service = _sessions[sessionId]?.sshService;
    if (service == null) return;
    if (ruleType == 'local') {
      service.stopLocalForward(ruleId);
    } else {
      service.stopRemoteForward(ruleId);
    }
  }

  /// How long a live transport gets to answer before it is treated as stalled.
  /// The health check catches a dead socket eventually, but an already-issued
  /// command can outlive that, and a fresh connection beats waiting on TCP.
  static const _liveClientStallTimeout = Duration(seconds: 8);

  SSHClient? _liveClientFor(String profileId) {
    for (final session in _sessions.values) {
      if (session.profile.id != profileId || session.dropped) continue;
      final client = session.sshService?.client;
      if (client != null && !client.isClosed) return client;
    }
    return null;
  }

  /// Runs [operation] over this profile's live transport when one is up, and
  /// over a short-lived connection otherwise.
  ///
  /// A full handshake is a TCP round trip, a key exchange and an auth - far
  /// too much to pay on a mobile link for a single `list` when a connection
  /// to the same host is already open.
  ///
  /// [idempotent] marks an operation that is safe to run twice, which is what
  /// allows a stalled live transport to be abandoned for a fresh connection.
  /// A rename or a kill cannot be replayed, so those report the failure
  /// instead of risking a second execution.
  /// [cancel] gives up on the operation the moment it trips. Over a live
  /// transport that is only this caller's wait being abandoned - the session
  /// it belongs to is somebody else's and stays up. Over a short-lived
  /// connection it tears the connection down, which is the difference between
  /// stopping a load and merely looking away from one.
  Future<T> _withClient<T>(
    SshProfile profile,
    Future<T> Function(SSHClient client) operation, {
    bool idempotent = false,
    CancelToken? cancel,
  }) async {
    final live = _liveClientFor(profile.id);
    if (live == null) {
      return _withTemporaryClient(profile, operation, cancel: cancel);
    }
    if (!idempotent) return _race(cancel, operation(live));
    try {
      return await _race(
        cancel,
        operation(live).timeout(_liveClientStallTimeout),
      );
    } on TimeoutException {
      return _withTemporaryClient(profile, operation, cancel: cancel);
    }
  }

  /// Connects with [profile] and disconnects again, for the form's "Test
  /// connection" - the same path, prompts and failures a first session would
  /// hit, so a host key accepted here is the one that session will expect.
  /// Throws what [SshService.connect] throws.
  Future<void> testConnection(SshProfile profile, {CancelToken? cancel}) =>
      _withTemporaryClient(profile, (_) async {}, cancel: cancel);

  /// Opens a short-lived [SSHClient] for [profile], runs [operation] on it
  /// and disconnects again.
  ///
  /// Carries the same host-key and keyboard-interactive prompts as a
  /// foreground connection: a session list or a rename is user-initiated
  /// too, and the first contact with a host can just as easily happen here
  /// as on a tab. The `finally` disconnect also runs on the cancelled path,
  /// which is what actually stops the handshake rather than leaving it to
  /// finish into nothing.
  Future<T> _withTemporaryClient<T>(
    SshProfile profile,
    Future<T> Function(SSHClient client) operation, {
    CancelToken? cancel,
  }) async {
    final service = _serviceFactory();
    try {
      cancel?.throwIfCancelled();
      await _race(
        cancel,
        service.connect(
          profile,
          onHostKeyPrompt: hostKeyPrompt,
          onKeyboardInteractive: keyboardInteractivePrompt,
        ),
      );
      return await _race(cancel, operation(service.client!));
    } finally {
      await service.disconnect();
    }
  }

  Future<T> _race<T>(CancelToken? cancel, Future<T> operation) =>
      cancel == null ? operation : cancel.race(operation);

  void _handleCwdMarker(ActiveSessionView session, String payload) {
    const prefix = '5382;termphin-cwd;';
    if (!payload.startsWith(prefix)) return;
    final cwd = payload.substring(prefix.length);
    if (cwd.isNotEmpty) session.reportedCwd = cwd;
  }

  void _handleSnippetMarker(String payload) {
    const prefix = '5379;termphin;';
    if (!payload.startsWith(prefix)) return;
    final parts = payload.substring(prefix.length).split(';');
    if (parts.length != 2 || parts.first.isEmpty) return;
    final exitCode = int.tryParse(parts.last);
    if (exitCode == null) return;
    for (final listener in _snippetRunListeners.toList()) {
      listener(parts.first, exitCode);
    }
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
      unawaited(session.sshService?.disconnect());
    }
    _sessions.clear();
    _snippetRunListeners.clear();
    super.dispose();
  }
}
