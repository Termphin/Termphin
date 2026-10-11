import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../services/ssh/ssh_service.dart';
import '../services/terminal/osc_markers.dart';
import '../services/terminal/terminal_modes.dart';
import 'remote_shell.dart';
import 'session_tab.dart';
import 'ssh_profile.dart';

/// Bytes sent to the shell, and their place in the order they went out.
typedef SessionInput = ({int seq, Uint8List bytes});

/// UI-side representation of an SSH session owned by Dart.
class ActiveSessionView {
  ActiveSessionView({
    required this.id,
    required this.profile,
    required this.connectedAt,
    this.remoteShellType = RemoteShellType.unknown,
    this.muxName,
    this.multiplexer = Multiplexer.none,
    this.sshService,
    this.isRun = false,
    this.connecting = false,
  }) : _outputController = StreamController<Uint8List>.broadcast();

  final String id;
  SshProfile profile;
  final DateTime connectedAt;
  RemoteShellType remoteShellType;

  /// Replaced when a dropped session is resumed in place.
  SshService? sshService;

  /// Where in the agent's output the next byte this session expects stands,
  /// once the agent has said. What a reconnect resumes from.
  OutputPosition? outputPosition;

  /// Whether the last attach continued this session's output rather than
  /// replaying it, so the terminal already on screen is still right.
  bool resumedInPlace = false;

  /// The remote scratch directory a fast upload lands in, resolved from the
  /// shell's own idea of its temp folder on first use and cached here so a
  /// second upload in the same session doesn't pay for another round trip.
  String? resolvedTmpDirectory;

  /// True for the throwaway session behind a snippet run, which is what keeps
  /// it out of the tab bar and out of the active-session count.
  final bool isRun;

  /// Multiplexer session name this tab attaches to, if persistence is possible.
  /// Mutable so a successful rename can update it in place.
  String? muxName;

  /// Multiplexer actually used by the last successful attach.
  Multiplexer multiplexer;

  /// The agent binary the last attach ran, and whether it runs on Windows.
  /// What ending the session reuses instead of probing the host again.
  ({String path, bool isWindows})? agentBinary;

  /// Whether this connection had to upload the agent binary before it could
  /// attach. That upload is the whole difference between a first connect to a
  /// machine and every later one, and without it the two are one undivided
  /// number that says nothing about how long anybody actually waits.
  bool agentInstalled = false;

  /// The shell's own last-reported working directory, from the
  /// `termphin-cwd` OSC marker its prompt emits on Windows - PowerShell's
  /// `cd` doesn't update the OS-level process directory the way a POSIX
  /// shell's does, so there is nothing external to read there the way the
  /// agent reads `/proc/<pid>/cwd` on Unix.
  String? reportedCwd;

  late final StreamController<Uint8List> _outputController;
  Stream<Uint8List> get outputStream => _outputController.stream;

  /// Every byte sent to the shell, whoever sent it - keyboard, toolbar, paste
  /// or snippet - numbered in order. Synchronous, so a keystroke is predicted
  /// before the frame it was typed in is drawn.
  final StreamController<SessionInput> _inputController =
      StreamController<SessionInput>.broadcast(sync: true);
  Stream<SessionInput> get inputStream => _inputController.stream;

  /// The highest input number the server has confirmed receiving.
  final StreamController<int> _receiptController =
      StreamController<int>.broadcast();
  Stream<int> get inputReceipts => _receiptController.stream;

  int _inputSeq = 0;
  int get inputSeq => _inputSeq;

  /// A receipt is being asked for, and whether more input went out since.
  bool confirmingInput = false;
  bool inputAwaitingReceipt = false;

  void noteInput(Uint8List bytes) {
    _inputSeq++;
    if (!_inputController.isClosed) {
      _inputController.add((seq: _inputSeq, bytes: bytes));
    }
  }

  void noteInputReceived(int seq) {
    if (!_receiptController.isClosed) _receiptController.add(seq);
  }

  final StreamController<void> _rebootRestoredController =
      StreamController<void>.broadcast();
  Stream<void> get rebootRestoredEvents => _rebootRestoredController.stream;
  void notifyRebootRestored() {
    if (!_rebootRestoredController.isClosed) {
      _rebootRestoredController.add(null);
    }
  }

  final List<Uint8List> _rawHistory = [];
  int _rawHistorySize = 0;
  static const _maxRawHistoryBytes = 512 * 1024;

  final TerminalModeTracker _trimmedModes = TerminalModeTracker();

  StreamSubscription<Uint8List>? serviceOutputSubscription;
  StreamSubscription<void>? sessionDoneSubscription;

  bool dropped = false;

  /// True from the moment the session is registered until its shell is
  /// attached. `startSession` publishes the session before the handshake even
  /// starts, so without this a connection still negotiating is indistinguishable
  /// from a live one - which is what made a machine's list read "Connected, 0m"
  /// for the whole of a slow connect.
  bool connecting;

  /// Raw replay stored for a terminal widget that is about to mount.
  Uint8List? pendingReplay;

  Future<SSHClient> get sftpClient async {
    final client = sshService?.client;
    if (client == null || client.isClosed) {
      throw Exception('SSH session is not connected.');
    }
    return client;
  }

  Duration get uptime => DateTime.now().difference(connectedAt);

  void deliverOutput(Uint8List bytes) {
    if (_outputController.isClosed) return;
    final copy = Uint8List.fromList(bytes);
    _rawHistory.add(copy);
    _rawHistorySize += copy.length;
    while (_rawHistorySize > _maxRawHistoryBytes && _rawHistory.isNotEmpty) {
      final dropped = _rawHistory.removeAt(0);
      _rawHistorySize -= dropped.length;
      _trimmedModes.consume(dropped);
    }
    _outputController.add(copy);
  }

  /// Starts the history over from [bytes] - a replay that replaced it.
  void replaceHistory(Uint8List bytes) {
    _rawHistory.clear();
    _rawHistorySize = 0;
    _trimmedModes.reset();
    if (bytes.isEmpty) return;
    final cut = bytes.length - _maxRawHistoryBytes;
    if (cut > 0) _trimmedModes.consume(Uint8List.sublistView(bytes, 0, cut));
    final kept = cut > 0 ? Uint8List.sublistView(bytes, cut) : bytes;
    _rawHistory.add(Uint8List.fromList(kept));
    _rawHistorySize = kept.length;
  }

  Uint8List get rawHistorySnapshot {
    final prefix = _trimmedModes.restoreSequence;
    final result = Uint8List(prefix.length + _rawHistorySize)
      ..setRange(0, prefix.length, prefix);
    var offset = prefix.length;
    for (final chunk in _rawHistory) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  String get uptimeFormatted {
    final d = uptime;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  /// Closed for good - by a detach or an end, not a dropped transport. Its
  /// output stream is shut, so nothing may be resumed onto it.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    unawaited(serviceOutputSubscription?.cancel());
    serviceOutputSubscription = null;
    unawaited(sessionDoneSubscription?.cancel());
    sessionDoneSubscription = null;
    _rawHistory.clear();
    _rawHistorySize = 0;
    _trimmedModes.reset();
    if (!_outputController.isClosed) {
      unawaited(_outputController.close());
    }
    if (!_rebootRestoredController.isClosed) {
      unawaited(_rebootRestoredController.close());
    }
    if (!_inputController.isClosed) {
      unawaited(_inputController.close());
    }
    if (!_receiptController.isClosed) {
      unawaited(_receiptController.close());
    }
  }
}
