import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'package:termphin/services/ssh/ssh_service.dart';

const _dirMode = 1 << 14;
const _fileMode = 1 << 15;

SftpName sftpDir(String name, {int? modifyTime}) => SftpName(
  filename: name,
  longname: name,
  attr: SftpFileAttrs(
    mode: const SftpFileMode.value(_dirMode),
    modifyTime: modifyTime,
  ),
);

SftpName sftpFile(String name, {int size = 4, int? modifyTime}) => SftpName(
  filename: name,
  longname: name,
  attr: SftpFileAttrs(
    mode: const SftpFileMode.value(_fileMode),
    size: size,
    modifyTime: modifyTime,
  ),
);

class FakeSftpOpenFile implements SftpFile {
  FakeSftpOpenFile({this.onClose, List<int>? initial}) {
    if (initial != null) bytes.addAll(initial);
  }

  /// Handed the bytes written, so the tree can keep them - a real server does
  /// not forget a file the moment its handle is closed.
  final void Function(List<int> bytes)? onClose;

  final List<int> bytes = [];
  bool closed = false;

  @override
  Stream<Uint8List> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 16 * 1024,
    int maxPendingRequests = 64,
  }) async* {
    yield Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeBytes(
    Uint8List data, {
    int offset = 0,
    int chunkSize = 16 * 1024,
    int maxPendingRequests = 64,
  }) async {
    bytes.addAll(data);
  }

  @override
  Future<void> close() async {
    closed = true;
    onClose?.call(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory directory tree backing [FakeSftpClient] - directory path to its
/// listing, mutated by mkdir/rmdir/remove/rename so a widget's refresh after
/// an action sees the result.
class FakeSftpTree {
  FakeSftpTree(this.children, {Map<String, String>? contents})
    : contents = contents ?? <String, String>{};

  final Map<String, List<SftpName>> children;

  /// File path to its text. Only what a test has put there; anything else
  /// reads as empty, the way an untouched fixture always did.
  final Map<String, String> contents;

  String cwd = '/home/user';

  (String, String) _split(String path) {
    final slash = path.lastIndexOf('/');
    if (slash <= 0) return ('/', path.substring(slash + 1));
    return (path.substring(0, slash), path.substring(slash + 1));
  }
}

/// A fake standing in for the real dartssh2 [SftpClient] - enough of the
/// surface [SftpService] and [SftpBrowserView] use, backed by [FakeSftpTree]
/// so create/delete/rename show up in the next listing the way the real
/// server's would.
class FakeSftpClient implements SftpClient {
  FakeSftpClient(this.tree);

  final FakeSftpTree tree;
  final List<String> listedPaths = [];
  Object? nextError;

  /// Every path removed, file or folder, in order.
  final List<String> removedPaths = [];

  /// Thrown by a rename of that source path, every time.
  final Map<String, Object> renameErrors = {};

  /// Holds up [listdir] for a path until released, so a test can make an
  /// older navigation's listing resolve after a newer one's.
  final Map<String, Completer<void>> _listingGates = {};

  void gateListing(String path) => _listingGates[path] = Completer<void>();

  void releaseListing(String path) => _listingGates.remove(path)?.complete();

  void _throwIfNeeded() {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  @override
  Future<List<SftpName>> listdir(String path) async {
    _throwIfNeeded();
    listedPaths.add(path);
    final gate = _listingGates[path];
    if (gate != null) await gate.future;
    final entries = tree.children[path];
    if (entries == null) {
      throw SftpStatusError(SftpStatusCode.noSuchFile, 'no such directory');
    }
    return entries;
  }

  @override
  Future<String> absolute(String path) async {
    if (path == '.') return tree.cwd;
    return path;
  }

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    _throwIfNeeded();
    if (tree.children.containsKey(path)) {
      return SftpFileAttrs(mode: const SftpFileMode.value(_dirMode));
    }
    final (parent, name) = tree._split(path);
    final entry = tree.children[parent]?.where((e) => e.filename == name);
    if (entry == null || entry.isEmpty) {
      throw SftpStatusError(SftpStatusCode.noSuchFile, 'missing');
    }
    return entry.first.attr;
  }

  @override
  Future<void> mkdir(String path, [SftpFileAttrs? attrs]) async {
    _throwIfNeeded();
    final (parent, name) = tree._split(path);
    tree.children[path] = [];
    tree.children[parent]?.add(sftpDir(name));
  }

  @override
  Future<void> remove(String filename) async {
    _throwIfNeeded();
    removedPaths.add(filename);
    final (parent, name) = tree._split(filename);
    tree.children[parent]?.removeWhere((e) => e.filename == name);
  }

  @override
  Future<void> rmdir(String dirname) async {
    _throwIfNeeded();
    removedPaths.add(dirname);
    tree.children.remove(dirname);
    final (parent, name) = tree._split(dirname);
    tree.children[parent]?.removeWhere((e) => e.filename == name);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    _throwIfNeeded();
    final refused = renameErrors[oldPath];
    if (refused != null) throw refused;
    final (oldParent, oldName) = tree._split(oldPath);
    final (newParent, newName) = tree._split(newPath);
    final siblings = tree.children[oldParent];
    if (siblings == null) return;
    final index = siblings.indexWhere((e) => e.filename == oldName);
    if (index == -1) return;
    final moved = siblings.removeAt(index);
    final movedContent = tree.contents.remove(oldPath);
    if (movedContent != null) tree.contents[newPath] = movedContent;
    final renamed = moved.attr.isDirectory
        ? sftpDir(newName, modifyTime: moved.attr.modifyTime)
        : sftpFile(
            newName,
            size: moved.attr.size ?? 0,
            modifyTime: moved.attr.modifyTime,
          );
    final destination = tree.children[newParent] ??= [];
    destination.removeWhere((entry) => entry.filename == newName);
    destination.add(renamed);
    if (moved.attr.isDirectory) {
      final subtree = tree.children.remove(oldPath);
      if (subtree != null) tree.children[newPath] = subtree;
    }
  }

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    _throwIfNeeded();
    return FakeSftpOpenFile(
      initial: utf8.encode(tree.contents[path] ?? ''),
      onClose: (bytes) {
        if (bytes.isEmpty && !tree.contents.containsKey(path)) return;
        tree.contents[path] = utf8.decode(bytes, allowMalformed: true);
        final (parent, name) = tree._split(path);
        final siblings = tree.children[parent] ??= [];
        siblings
          ..removeWhere((entry) => entry.filename == name)
          ..add(sftpFile(name, size: bytes.length, modifyTime: nextMtime));
      },
    );
  }

  /// What a file written from now on is stamped with. A test bumps this to
  /// stand in for someone else having touched the file since it was opened.
  int? nextMtime;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What a fake server answers a command with.
typedef FakeCommandResult = ({int? exitCode, String stdout, String stderr});

/// One exec channel's worth of [SSHSession]: output already there, stdin
/// recorded as closed so a test can check nothing is left waiting on it.
class FakeSshSession implements SSHSession {
  FakeSshSession(this.result) {
    _stdin.stream.listen(null, onDone: () => stdinClosed = true);
  }

  final FakeCommandResult result;
  // ignore: close_sinks
  final _stdin = StreamController<Uint8List>();
  bool stdinClosed = false;

  @override
  StreamSink<Uint8List> get stdin => _stdin.sink;

  @override
  Stream<Uint8List> get stdout =>
      Stream.value(Uint8List.fromList(utf8.encode(result.stdout)));

  @override
  Stream<Uint8List> get stderr =>
      Stream.value(Uint8List.fromList(utf8.encode(result.stderr)));

  @override
  int? get exitCode => result.exitCode;

  @override
  Future<void> get done async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSftpSshClient implements SSHClient {
  FakeSftpSshClient(this.sftpClient, {this.onCommand});

  final FakeSftpClient sftpClient;

  /// Answers every exec. Unset, the server runs no commands at all - the
  /// shape of an account locked to SFTP.
  FutureOr<FakeCommandResult> Function(String command)? onCommand;
  final List<String> commands = [];

  @override
  bool get isClosed => false;

  @override
  Future<SftpClient> sftp() async => sftpClient;

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    commands.add(command);
    final handler = onCommand;
    return FakeSshSession(
      handler == null
          ? (exitCode: 0, stdout: '', stderr: '')
          : await handler(command),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [SshService] whose [client] is a fake wired to a [FakeSftpClient], so
/// [ActiveSessionView.sftpClient] resolves without a real SSH connection.
class FakeSftpSshService extends SshService {
  FakeSftpSshService(FakeSftpClient sftpClient)
    : fakeClient = FakeSftpSshClient(sftpClient);

  final FakeSftpSshClient fakeClient;

  @override
  SSHClient? get client => fakeClient;
}
