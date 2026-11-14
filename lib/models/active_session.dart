import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../services/ssh/ssh_service.dart';
import '../services/terminal/osc_markers.dart';
import '../services/terminal/session_terminal.dart';
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
    int columns = 80,
    int rows = 24,
  }) : _columns = columns,
       _rows = rows,
       _outputController = StreamController<Uint8List>.broadcast();

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

  /// The terminal every byte of output is parsed into as it arrives, whether
  /// or not a pane is showing it. Replaced by [restartTerminal].
  ///
  /// Made on first use: the tabs restored at launch are sessions too, each
  /// would hold a scrollback ring it may never write to.
  SessionTerminal get terminal => _terminal ??= SessionTerminal(
    columns: _columns,
    rows: _rows,
    onReply: _replyFromTerminal,
  );
  SessionTerminal? _terminal;
  int _columns;
  int _rows;

  /// The size the pty is about to be opened with, for a session that has no
  /// terminal yet - a tab restored at launch, connecting for the first time.
  /// One that has a terminal keeps its size: a pane laid it out.
  void ptyOpensAt(int columns, int rows) {
    if (_terminal != null) return;
    _columns = columns;
    _rows = rows;
  }

  StreamSubscription<Uint8List>? serviceOutputSubscription;
  StreamSubscription<void>? sessionDoneSubscription;

  bool dropped = false;

  /// True from the moment the session is registered until its shell is
  /// attached. `startSession` publishes the session before the handshake even
  /// starts, so without this a connection still negotiating is indistinguishable
  /// from a live one - which is what made a machine's list read "Connected, 0m"
  /// for the whole of a slow connect.
  bool connecting;

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
    terminal.add(copy);
    _outputController.add(copy);
  }

  /// Starts the terminal over from [replay] - the agent's own picture of the
  /// session, sent when it could not just continue from where this one
  /// stopped. A new terminal rather than a cleared one: the pane showing the
  /// old one keeps it on screen until the pane for this one is ready.
  void restartTerminal(Uint8List replay) {
    if (_disposed) return;
    final previous = _terminal;
    _terminal = SessionTerminal(
      columns: previous?.terminal.viewWidth ?? _columns,
      rows: previous?.terminal.viewHeight ?? _rows,
      replay: replay,
      onReply: _replyFromTerminal,
    );
    previous?.retire();
  }

  /// What the terminal answers the program with while no pane is mounted to
  /// send it. Not noted as input: nobody typed it.
  void _replyFromTerminal(String data) {
    if (dropped || _disposed) return;
    sshService?.write(Uint8List.fromList(utf8.encode(data)));
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
    _terminal?.retire();
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
