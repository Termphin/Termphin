import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/strings.g.dart';
import '../models/session_tab.dart';
import '../models/ssh_profile.dart';
import '../services/analytics/analytics_service.dart';
import '../services/app/identity_anonymizer.dart';
import '../services/app/review_prompt_service.dart';
import '../services/platform/local_notifications_service.dart';
import '../services/ssh/keepalive_pinger.dart';
import '../services/ssh/network_monitor.dart';
import '../services/ssh/ssh_service.dart';
import '../services/ssh/ssh_session_manager.dart';
import '../services/terminal/reconnect_input_buffer.dart';
import 'anonymize_provider.dart';
import 'network_monitor_provider.dart';
import 'port_forwarding_provider.dart';
import 'profiles_provider.dart';
import 'ssh_session_manager_provider.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

class SshConnectionState {
  const SshConnectionState({
    required this.status,
    this.errorMessage,
    this.failureReason,
    this.connectionLog = const [],
    this.disconnectedByDrop = false,
    this.reconnectAttempt = 0,
    this.reconnectSecondsRemaining = 0,
    this.waitingForNetwork = false,
    this.multiplexer = Multiplexer.none,
    this.attachId = 0,
    this.queuedInput = 0,
  });

  final ConnectionStatus status;
  final String? errorMessage;

  /// What [errorMessage] is, as a value the UI can translate. The message
  /// itself is written where it is thrown and interpolates addresses and
  /// driver text, so it stays the fallback rather than what is shown.
  final SshFailureReason? failureReason;

  final List<String> connectionLog;
  final bool disconnectedByDrop;
  final int reconnectAttempt;

  /// Counts down to the next retry while [status] is [ConnectionStatus.reconnecting].
  final int reconnectSecondsRemaining;

  /// Parked until the device has a network again. There is no countdown in
  /// this state and no attempt is spent - retrying into a radio that is off
  /// only lengthens the backoff the real reconnect will wait out.
  final bool waitingForNetwork;

  /// Multiplexer that backed the last successful attach. [Multiplexer.none]
  /// means the remote session dies with the transport.
  final Multiplexer multiplexer;

  /// Bumped on every successful attach. The terminal widget keys off this
  /// instead of the transient status flicker, since Riverpod can settle on
  /// `connected` again before Flutter ever paints the frame in between -
  /// a status-based reset can be scheduled for a widget that never actually
  /// gets torn down and never fires `onReady` again.
  final int attachId;

  /// Characters typed during a reconnect, waiting to be sent.
  final int queuedInput;

  SshConnectionState copyWith({
    ConnectionStatus? status,
    String? errorMessage,
    SshFailureReason? failureReason,
    List<String>? connectionLog,
    bool clearError = false,
    bool clearConnectionLog = false,
    bool? disconnectedByDrop,
    int? reconnectAttempt,
    int? reconnectSecondsRemaining,
    bool? waitingForNetwork,
    Multiplexer? multiplexer,
    int? attachId,
    int? queuedInput,
  }) {
    return SshConnectionState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      failureReason: clearError ? null : (failureReason ?? this.failureReason),
      connectionLog: clearConnectionLog
          ? const []
          : (connectionLog ?? this.connectionLog),
      disconnectedByDrop: disconnectedByDrop ?? this.disconnectedByDrop,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      reconnectSecondsRemaining:
          reconnectSecondsRemaining ?? this.reconnectSecondsRemaining,
      waitingForNetwork: waitingForNetwork ?? this.waitingForNetwork,
      multiplexer: multiplexer ?? this.multiplexer,
      attachId: attachId ?? this.attachId,
      queuedInput: queuedInput ?? this.queuedInput,
    );
  }
}

final sshConnectionProvider =
    NotifierProvider.family<
      SshConnectionNotifier,
      SshConnectionState,
      (String, SshProfile)
    >(SshConnectionNotifier.new);

class SshConnectionNotifier extends Notifier<SshConnectionState> {
  SshConnectionNotifier(this._key);

  final (String, SshProfile) _key;
  String get _sessionId => _key.$1;

  /// The key holds the profile as it was when the tab opened. An edit made
  /// since - a new host, say - has to reach the next connection attempt.
  SshProfile get _profile {
    final id = _key.$2.id;
    return ref.read(profilesProvider).where((p) => p.id == id).firstOrNull ??
        _key.$2;
  }

  /// Wait before transport-only retry [attempt] (from 1). The remote session
  /// keeps the shell, so retries go on for as long as the failure is one
  /// that can pass. The first goes at once: noticing the drop already took
  /// seconds.
  static Duration reconnectDelay(int attempt) {
    if (attempt <= 1) return Duration.zero;
    final seconds = 1 << math.min(attempt - 2, 5);
    return Duration(seconds: math.min(seconds, _maxReconnectDelaySeconds));
  }

  static const _maxReconnectDelaySeconds = 30;

  /// Failures no retry can fix: the same credentials, key or host key will be
  /// refused the same way again.
  static bool _isPermanent(SshFailureReason reason) => switch (reason) {
    SshFailureReason.authFailed ||
    SshFailureReason.authError ||
    SshFailureReason.hostKeyRejected ||
    SshFailureReason.hostKeyMismatch ||
    SshFailureReason.keyMissing ||
    SshFailureReason.keyPassphrase ||
    SshFailureReason.keyInvalid ||
    SshFailureReason.jumpHostConfig ||
    SshFailureReason.localNetworkBlocked => true,
    _ => false,
  };

  /// How often a parked retry re-reads the network for itself. Parking waits
  /// on a comeback event, and an event that was broadcast while the process
  /// was frozen never arrives - without this the wait has no end.
  static const _networkRecheckSeconds = 20;

  late final SshSessionManager _manager;
  late final NetworkMonitor _network;
  VoidCallback? _managerListener;
  StreamSubscription<void>? _networkSubscription;
  bool _disposed = false;
  bool _wasConnected = false;
  Timer? _reconnectTimer;
  Timer? _networkRecheckTimer;
  int _reconnectAttempt = 0;
  int _reconnectSecondsRemaining = 0;
  int _lastWidth = 80;
  int _lastHeight = 24;

  /// When the attempt now in flight started, so both outcomes can report how
  /// long it took. Wall clock rather than a stopwatch: the attempt spans
  /// awaits the notifier does not own, and a stopwatch left running across a
  /// disposal would be one more thing to tear down.
  DateTime? _attemptStarted;

  /// When the current outage was noticed, until the session is back or the
  /// retries end.
  DateTime? _droppedAt;

  final _queuedInput = ReconnectInputBuffer();

  int? get _attemptMs {
    final started = _attemptStarted;
    return started == null
        ? null
        : DateTime.now().difference(started).inMilliseconds;
  }

  @override
  SshConnectionState build() {
    _disposed = false;
    _wasConnected = false;
    _manager = ref.read(sshSessionManagerProvider);
    _network = ref.read(networkMonitorProvider);
    _networkSubscription = _network.onRegained.listen(
      (_) => _onNetworkRegained(),
    );
    ref.onDispose(() {
      _disposed = true;
      _cancelReconnect();
      _removeManagerListener();
      unawaited(_networkSubscription?.cancel());
      _networkSubscription = null;
    });
    return const SshConnectionState(status: ConnectionStatus.disconnected);
  }

  /// The radio coming back is better news than any timer: retry at once, and
  /// start the backoff over, since the attempts that failed while there was
  /// no network never tested anything.
  void _onNetworkRegained() {
    if (_disposed) return;
    if (state.status != ConnectionStatus.reconnecting) return;
    _cancelReconnect();
    _reconnectAttempt = 1;
    _reconnectSecondsRemaining = 0;
    state = state.copyWith(
      waitingForNetwork: false,
      reconnectAttempt: _reconnectAttempt,
      reconnectSecondsRemaining: 0,
    );
    unawaited(_connect(initialWidth: _lastWidth, initialHeight: _lastHeight));
  }

  Future<void> connect({int initialWidth = 80, int initialHeight = 24}) async {
    _cancelReconnect();
    _reconnectAttempt = 0;
    _reconnectSecondsRemaining = 0;
    await _connect(initialWidth: initialWidth, initialHeight: initialHeight);
  }

  /// Always asks the remote session to replay: every branch that reaches the
  /// `startSession` call below builds a brand new transport while the tab
  /// shows the connecting/reconnecting state, so nothing survives locally
  /// that the replay could duplicate. Only a reconnect has a terminal still
  /// on screen to continue in place.
  Future<void> _connect({
    required int initialWidth,
    required int initialHeight,
  }) async {
    _lastWidth = initialWidth;
    _lastHeight = initialHeight;
    _attemptStarted = DateTime.now();

    final existing = _manager.getSession(_sessionId);
    if (existing != null && !existing.dropped) {
      state = state.copyWith(
        status: ConnectionStatus.connecting,
        clearError: true,
        disconnectedByDrop: false,
      );
      await _attachToSession(resumed: true);
      return;
    }

    if (existing != null &&
        existing.dropped &&
        !_manager.canResume(_sessionId)) {
      await _manager.disconnectSession(_sessionId);
    }

    final reconnecting = _reconnectAttempt > 0;
    state = state.copyWith(
      status: reconnecting
          ? ConnectionStatus.reconnecting
          : ConnectionStatus.connecting,
      clearError: true,
      clearConnectionLog: !reconnecting,
      disconnectedByDrop: false,
      waitingForNetwork: false,
      reconnectAttempt: _reconnectAttempt,
    );

    try {
      final session = await _manager.startSession(
        _profile,
        sessionId: _sessionId,
        initialWidth: initialWidth,
        initialHeight: initialHeight,
        replayRemoteHistory: true,
        resume: true,
        onConnectionLog: _appendConnectionLog,
      );
      if (_disposed) return;
      state = state.copyWith(multiplexer: session.multiplexer);
      await _attachToSession(
        resumed: false,
        inPlace: reconnecting && session.resumedInPlace,
      );
    } catch (error) {
      if (_disposed) return;
      final msg = error.toString().replaceFirst('Exception: ', '');
      final reason = SshFailureReason.of(error);
      _appendConnectionLog(msg);
      unawaited(
        AnalyticsService.instance.capture(
          AnalyticsEvent.connectionFailed,
          properties: {
            ..._profileProperties(),
            AnalyticsProperty.reason: reason.reasonName,
            AnalyticsProperty.retry: reconnecting,
            AnalyticsProperty.durationMs: ?_attemptMs,
          },
        ),
      );
      if (!_isPermanent(reason) && _scheduleReconnect()) return;
      _droppedAt = null;
      _dropQueuedInput();
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: msg,
        failureReason: reason,
        waitingForNetwork: false,
      );
      _notifySessionDropped();
    }
  }

  /// Tells the server the terminal's size, and keeps it for the next
  /// connect: a reconnect opens a new PTY, and one opened at the size of the
  /// first connect stays wrong until the view happens to change size again.
  void resize(int width, int height) {
    _lastWidth = width;
    _lastHeight = height;
    _manager.resize(_sessionId, width, height);
  }

  /// Drops the transport and connects again, keeping the tab (and therefore
  /// its persistent session name) intact.
  Future<void> reconnect() async {
    _cancelReconnect();
    _reconnectAttempt = 0;
    _reconnectSecondsRemaining = 0;
    _removeManagerListener();
    await _manager.disconnectSession(_sessionId);
    if (_disposed) return;
    await _connect(initialWidth: _lastWidth, initialHeight: _lastHeight);
  }

  /// Retries after [reconnectDelay], ticking
  /// [SshConnectionState.reconnectSecondsRemaining] down every second so the
  /// UI can show a countdown. Returns false when the shell did not survive
  /// the drop, so there is nothing to go back to.
  ///
  /// With no network there is nothing to count down to, so the retry parks on
  /// [NetworkMonitor.onRegained] instead and spends no attempt - a phone in a
  /// tunnel would otherwise climb to the longest backoff against a radio that
  /// is off. An immediate retry still goes through a zero-delay [Timer]
  /// rather than a direct call, since this runs inside the manager's
  /// listener.
  bool _scheduleReconnect() {
    if (_disposed) return false;
    if (!state.multiplexer.isPersistent) return false;

    if (!_network.isOnline) {
      _cancelReconnect();
      _reconnectSecondsRemaining = 0;
      state = state.copyWith(
        status: ConnectionStatus.reconnecting,
        clearError: true,
        waitingForNetwork: true,
        reconnectAttempt: _reconnectAttempt,
        reconnectSecondsRemaining: 0,
      );
      _startNetworkRecheck();
      return true;
    }

    _reconnectAttempt++;
    _reconnectSecondsRemaining = reconnectDelay(_reconnectAttempt).inSeconds;
    state = state.copyWith(
      status: ConnectionStatus.reconnecting,
      clearError: true,
      waitingForNetwork: false,
      reconnectAttempt: _reconnectAttempt,
      reconnectSecondsRemaining: _reconnectSecondsRemaining,
    );
    _reconnectTimer?.cancel();
    if (_reconnectSecondsRemaining <= 0) {
      _reconnectTimer = Timer(Duration.zero, () {
        _reconnectTimer = null;
        if (_disposed) return;
        unawaited(
          _connect(initialWidth: _lastWidth, initialHeight: _lastHeight),
        );
      });
      return true;
    }
    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) {
        _cancelReconnect();
        return;
      }
      _reconnectSecondsRemaining--;
      if (_reconnectSecondsRemaining <= 0) {
        _cancelReconnect();
        unawaited(
          _connect(initialWidth: _lastWidth, initialHeight: _lastHeight),
        );
        return;
      }
      state = state.copyWith(
        reconnectSecondsRemaining: _reconnectSecondsRemaining,
      );
    });
    return true;
  }

  /// Polls the platform while parked, so a comeback the monitor never heard
  /// about still ends the wait. The monitor turns a probe that flips back to
  /// online into an [NetworkMonitor.onRegained] event, which is the same path
  /// a live platform event takes - this only supplies the missing trigger.
  void _startNetworkRecheck() {
    _networkRecheckTimer = Timer.periodic(
      const Duration(seconds: _networkRecheckSeconds),
      (_) {
        if (_disposed || !state.waitingForNetwork) {
          _cancelReconnect();
          return;
        }
        unawaited(_network.refresh());
      },
    );
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _networkRecheckTimer?.cancel();
    _networkRecheckTimer = null;
  }

  void _appendConnectionLog(String message) {
    if (_disposed) return;
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    state = state.copyWith(connectionLog: [...state.connectionLog, normalized]);
  }

  /// [resumed] is true when this reattaches to a session the manager already
  /// had live (a tab switch, or the process surviving in the background)
  /// rather than one just freshly connected - it decides which analytics
  /// event the successful attach below reports.
  ///
  /// [inPlace] is an attach that continued the output of the terminal already
  /// on screen, which is then kept rather than rebuilt and so has its queued
  /// input flushed straight away.
  ///
  /// If the session disappears without [SshSessionManager.stripHoldsTab], it
  /// was detached or ended elsewhere - the home screen's session row reaches
  /// it through a notifier of its own, since a reconnect or profile reload
  /// leaves it holding a different profile instance than this key - and that
  /// was a decision, not a drop, so it is not retried.
  Future<void> _attachToSession({
    required bool resumed,
    bool inPlace = false,
  }) async {
    _removeManagerListener();

    void listener() {
      if (_disposed) return;
      final s = _manager.getSession(_sessionId);
      if (s == null || s.dropped) {
        _removeManagerListener();
        if (!_manager.stripHoldsTab(_sessionId)) {
          _cancelReconnect();
          ref.read(portForwardingProvider(_sessionId).notifier).stopAll();
          _setDisconnected();
          return;
        }
        _markDropped();
      }
    }

    _managerListener = listener;
    _manager.addListener(listener);

    final session = _manager.getSession(_sessionId);
    if (session != null && !session.dropped) {
      await _manager.requestReplay(_sessionId);
    }
    if (_disposed) return;
    final attached = _manager.getSession(_sessionId);
    if (attached == null || attached.dropped) {
      _removeManagerListener();
      _markDropped();
      return;
    }

    _reconnectAttempt = 0;
    _reconnectSecondsRemaining = 0;
    _wasConnected = true;
    state = state.copyWith(
      status: ConnectionStatus.connected,
      clearError: true,
      disconnectedByDrop: false,
      reconnectAttempt: 0,
      reconnectSecondsRemaining: 0,
      waitingForNetwork: false,
      multiplexer: attached.multiplexer,
      attachId: inPlace ? state.attachId : state.attachId + 1,
    );
    if (inPlace) flushQueuedInput();
    final reachedHost = attached.sshService?.connectedHost;
    unawaited(
      AnalyticsService.instance.capture(
        resumed
            ? AnalyticsEvent.sessionResumed
            : AnalyticsEvent.connectionSuccess,
        properties: {
          ..._profileProperties(),
          AnalyticsProperty.multiplexer: attached.multiplexer.name,
          AnalyticsProperty.agentInstalled: attached.agentInstalled,
          AnalyticsProperty.durationMs: ?_attemptMs,
          if (_droppedAt != null) AnalyticsProperty.inPlace: inPlace,
          if (_droppedAt case final droppedAt?)
            AnalyticsProperty.downtimeMs: clock
                .now()
                .difference(droppedAt)
                .inMilliseconds,
          if (reachedHost != null)
            AnalyticsProperty.usedFallback: reachedHost != _profile.host,
        },
      ),
    );
    _droppedAt = null;
    unawaited(ReviewPromptService.instance.recordSuccessfulConnection());

    final notifier = ref.read(profilesProvider.notifier);
    await notifier.touchLastConnected(_profile.id);
    if (reachedHost != null) {
      await notifier.updateLastGoodHost(_profile.id, reachedHost);
    }
    if (_disposed) return;
    _startProfileTunnels();
  }

  void _startProfileTunnels() {
    final pfNotifier = ref.read(portForwardingProvider(_sessionId).notifier);
    pfNotifier.loadProfileRules(_profile);
    if (_profile.portForwardings.isNotEmpty) {
      pfNotifier.startAllProfileRules();
    }
  }

  /// The shape of the connection, with nothing identifying in it: how it
  /// authenticates, whether it goes through a bastion, how many alternative
  /// addresses it has - never the addresses themselves, the username or the
  /// profile's name.
  Map<AnalyticsProperty, Object> _profileProperties() => {
    AnalyticsProperty.authMethod: _profile.authMethod.name,
    AnalyticsProperty.viaJumpHost: _profile.jumpHostProfileId != null,
    AnalyticsProperty.fallbackCount: _profile.fallbackHosts
        .where((entry) => entry.trim().isNotEmpty)
        .length,
    AnalyticsProperty.portForwards: _profile.portForwardings.length,
  };

  /// With a multiplexer the shell survives on the server, so [_scheduleReconnect]
  /// gets to retry the transport before this bothers the user with an error.
  void _markDropped() {
    if (_disposed) return;
    _appendConnectionLog(t.connectionLog.connectionLost);
    _droppedAt ??= clock.now();
    final linkLoss = _manager.getSession(_sessionId)?.sshService?.linkLoss;
    unawaited(
      AnalyticsService.instance.capture(
        AnalyticsEvent.connectionDropped,
        properties: {
          ..._profileProperties(),
          AnalyticsProperty.multiplexer: state.multiplexer.name,
          AnalyticsProperty.lostVia: switch (linkLoss) {
            LinkLoss.silent => 'keepalive',
            LinkLoss.probe => 'probe',
            LinkLoss.closed || null => 'transport',
          },
        },
      ),
    );
    if (_scheduleReconnect()) return;
    _droppedAt = null;
    _dropQueuedInput();
    state = state.copyWith(
      status: ConnectionStatus.error,
      errorMessage: t.connectionLog.connectionLost,
      disconnectedByDrop: false,
      reconnectAttempt: 0,
      reconnectSecondsRemaining: 0,
    );
  }

  void write(List<int> bytes) {
    _manager.sendInput(_sessionId, Uint8List.fromList(bytes));
  }

  /// Holds [bytes] typed while reconnecting, for [flushQueuedInput] once the
  /// session is back. False when they were not held - the session is not
  /// reconnecting, or they are not plain text; see [ReconnectInputBuffer].
  bool queueInput(List<int> bytes) {
    if (state.status != ConnectionStatus.reconnecting) return false;
    if (!_queuedInput.add(bytes)) return false;
    state = state.copyWith(queuedInput: _queuedInput.characters);
    return true;
  }

  /// Sends what [queueInput] held. Left to the caller rather than done on
  /// attach, so the echo has a terminal on screen to land in.
  void flushQueuedInput() {
    if (state.status != ConnectionStatus.connected || _queuedInput.isEmpty) {
      return;
    }
    write(_queuedInput.take());
    state = state.copyWith(queuedInput: 0);
  }

  void _dropQueuedInput() {
    _queuedInput.clear();
    if (state.queuedInput != 0) state = state.copyWith(queuedInput: 0);
  }

  /// Closes the tab, leaving the multiplexer session running on the server.
  /// Throws what [SshSessionManager.stopSession] throws, with the state
  /// already set back to disconnected.
  Future<void> disconnect() async {
    _cancelReconnect();
    _removeManagerListener();
    ref.read(portForwardingProvider(_sessionId).notifier).stopAll();
    try {
      await _manager.stopSession(_sessionId);
    } finally {
      _setDisconnected();
    }
  }

  /// Closes the tab and kills the multiplexer session on the server. Throws
  /// what [SshSessionManager.endSession] throws, with the tab already closed.
  Future<void> endSession() async {
    _cancelReconnect();
    _removeManagerListener();
    ref.read(portForwardingProvider(_sessionId).notifier).stopAll();
    try {
      await _manager.endSession(_sessionId);
    } finally {
      _setDisconnected();
    }
  }

  void _setDisconnected() {
    _droppedAt = null;
    _dropQueuedInput();
    _reconnectAttempt = 0;
    _reconnectSecondsRemaining = 0;
    state = state.copyWith(
      status: ConnectionStatus.disconnected,
      clearError: true,
      disconnectedByDrop: false,
      reconnectAttempt: 0,
      reconnectSecondsRemaining: 0,
    );
  }

  void detach() {
    _cancelReconnect();
    _removeManagerListener();
    _droppedAt = null;
    _dropQueuedInput();
    state = state.copyWith(
      status: ConnectionStatus.disconnected,
      disconnectedByDrop: false,
    );
  }

  void validateAndReconnect() {
    if (_disposed) return;
    final session = _manager.getSession(_sessionId);
    if (session == null || session.dropped) {
      _markDropped();
    }
  }

  void _notifySessionDropped() {
    if (!_wasConnected) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) return;
    final anonymize = ref.read(anonymizeProvider);
    final name = anonymize
        ? IdentityAnonymizer.name(_profile.id)
        : _profile.name;
    unawaited(
      LocalNotificationsService.instance.showSessionDropped(name: name),
    );
  }

  void _removeManagerListener() {
    if (_managerListener != null) {
      _manager.removeListener(_managerListener!);
      _managerListener = null;
    }
  }
}
