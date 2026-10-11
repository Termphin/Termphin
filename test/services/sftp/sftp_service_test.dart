import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/sftp/cancel_token.dart';
import 'package:termphin/services/sftp/sftp_service.dart';

class _UnusedSshClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReconnectableSshClient implements SSHClient {
  _ReconnectableSshClient(this.sftpClient);

  final _FakeSftpClient sftpClient;
  bool closed = false;

  @override
  bool get isClosed => closed;

  @override
  Future<SftpClient> sftp() async {
    if (closed) throw SSHStateError('SSH connection closed');
    return sftpClient;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSftpFile implements SftpFile {
  _FakeSftpFile({this.chunks = const [], this.readError, this.writeError});

  final List<Uint8List> chunks;
  final Object? readError;
  final Object? writeError;
  final List<(int, Uint8List)> writes = [];
  bool closed = false;

  @override
  Stream<Uint8List> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 16 * 1024,
    int maxPendingRequests = 64,
  }) async* {
    var bytesRead = 0;
    for (final chunk in chunks) {
      bytesRead += chunk.length;
      onProgress?.call(bytesRead);
      yield chunk;
    }
    if (readError != null) throw readError!;
  }

  @override
  Future<void> writeBytes(
    Uint8List data, {
    int offset = 0,
    int chunkSize = 16 * 1024,
    int maxPendingRequests = 64,
  }) async {
    if (writeError != null) throw writeError!;
    writes.add((offset, Uint8List.fromList(data)));
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSftpClient implements SftpClient {
  List<SftpName> directoryEntries = [];
  SftpFileAttrs statResult = SftpFileAttrs();
  _FakeSftpFile file = _FakeSftpFile();
  Object? error;
  final List<String> listedPaths = [];
  final List<String> statPaths = [];
  final List<(String, int)> openedPaths = [];
  final List<String> removedPaths = [];
  final List<String> removedDirectories = [];
  final List<(String, String)> renames = [];
  bool closed = false;

  @override
  Future<void> close() async => closed = true;

  void _throwIfNeeded() {
    if (error != null) throw error!;
  }

  @override
  Future<List<SftpName>> listdir(String path) async {
    _throwIfNeeded();
    listedPaths.add(path);
    return directoryEntries;
  }

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    _throwIfNeeded();
    statPaths.add(path);
    return statResult;
  }

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    _throwIfNeeded();
    openedPaths.add((path, mode.flag));
    return file;
  }

  @override
  Future<void> remove(String filename) async {
    _throwIfNeeded();
    removedPaths.add(filename);
  }

  @override
  Future<void> rmdir(String dirname) async {
    _throwIfNeeded();
    removedDirectories.add(dirname);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    _throwIfNeeded();
    renames.add((oldPath, newPath));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fake with an actual directory tree behind it, for the recursive paths.
/// Mode bit patterns for the entry kinds the tree fake hands out.
const _dirMode = 1 << 14;
const _linkMode = (1 << 15) + (1 << 13);
const _fileMode = 1 << 15;

class _TreeSftpClient implements SftpClient {
  _TreeSftpClient(this.tree, {this.symlinks = const {}});

  /// Directory path → child names. A path missing from here is a file.
  final Map<String, List<String>> tree;

  /// Paths that are symlinks; the value says whether they point at a
  /// directory.
  final Map<String, bool> symlinks;

  final List<String> removedPaths = [];
  final List<String> removedDirectories = [];
  final List<String> listedPaths = [];

  bool _isDirectory(String path) => tree.containsKey(path);

  @override
  Future<List<SftpName>> listdir(String path) async {
    listedPaths.add(path);
    final children = tree[path];
    if (children == null) {
      throw SftpStatusError(SftpStatusCode.failure, 'not a directory');
    }
    return [
      for (final name in children)
        SftpName(
          filename: name,
          longname: name,
          attr: SftpFileAttrs(
            mode: SftpFileMode.value(
              symlinks.containsKey('$path/$name')
                  ? _linkMode
                  : _isDirectory('$path/$name')
                  ? _dirMode
                  : _fileMode,
            ),
            size: 4,
          ),
        ),
    ];
  }

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    final linkTarget = symlinks[path];
    if (linkTarget != null && !followLink) {
      return SftpFileAttrs(mode: const SftpFileMode.value(_linkMode));
    }
    if (linkTarget != null) {
      return SftpFileAttrs(
        mode: SftpFileMode.value(linkTarget ? _dirMode : _fileMode),
      );
    }
    if (!_isDirectory(path) && !_exists(path)) {
      throw SftpStatusError(SftpStatusCode.noSuchFile, 'missing');
    }
    return SftpFileAttrs(
      mode: SftpFileMode.value(_isDirectory(path) ? _dirMode : _fileMode),
      size: 4,
    );
  }

  bool _exists(String path) {
    if (tree.containsKey(path)) return true;
    final slash = path.lastIndexOf('/');
    if (slash <= 0) return false;
    final parent = path.substring(0, slash);
    return tree[parent]?.contains(path.substring(slash + 1)) ?? false;
  }

  @override
  Future<void> remove(String filename) async {
    if (_isDirectory(filename)) {
      throw SftpStatusError(SftpStatusCode.failure, 'is a directory');
    }
    if (!_exists(filename)) {
      throw SftpStatusError(SftpStatusCode.noSuchFile, 'missing');
    }
    removedPaths.add(filename);
    _detach(filename);
  }

  @override
  Future<void> rmdir(String dirname) async {
    final children = tree[dirname];
    if (children == null) {
      throw SftpStatusError(SftpStatusCode.failure, 'not a directory');
    }
    if (children.isNotEmpty) {
      throw SftpStatusError(SftpStatusCode.failure, 'not empty');
    }
    removedDirectories.add(dirname);
    tree.remove(dirname);
    _detach(dirname);
  }

  void _detach(String path) {
    final slash = path.lastIndexOf('/');
    if (slash <= 0) return;
    tree[path.substring(0, slash)]?.remove(path.substring(slash + 1));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Matcher _throwsSftpKey(String key) {
  return throwsA(
    isA<Exception>().having(
      (error) => error.toString(),
      'message',
      'Exception: $key',
    ),
  );
}

void main() {
  late _FakeSftpClient client;
  late SftpService service;
  late int openCount;

  setUp(() {
    client = _FakeSftpClient();
    openCount = 0;
    service = SftpService.test(_UnusedSshClient(), () async {
      openCount++;
      return client;
    });
  });

  test('opens SFTP lazily once and delegates metadata operations', () async {
    final entry = SftpName(
      filename: 'report.txt',
      longname: 'report.txt',
      attr: SftpFileAttrs(size: 12),
    );
    client.directoryEntries = [entry];
    client.statResult = SftpFileAttrs(size: 12);

    expect(await service.listDirectory('/remote'), [same(entry)]);
    expect((await service.stat('/remote/report.txt')).size, 12);

    expect(openCount, 1);
    expect(client.listedPaths, ['/remote']);
    expect(client.statPaths, ['/remote/report.txt']);
    expect(service.sftp, same(client));
  });

  test('close shuts the SFTP channel and the next call reopens it', () async {
    await service.stat('/remote/a');
    await service.close();
    expect(client.closed, isTrue);

    await service.stat('/remote/b');
    expect(openCount, 2);
  });

  test('close before any call opens nothing', () async {
    await service.close();
    expect(openCount, 0);
  });

  test('delegates file and directory mutations', () async {
    await service.deletePath('/remote/file.txt');
    await service.deletePath('/remote/folder', isDirectory: true);
    await service.rename('/remote/old', '/remote/new');

    expect(client.removedPaths, ['/remote/file.txt']);
    expect(client.removedDirectories, ['/remote/folder']);
    expect(client.renames, [('/remote/old', '/remote/new')]);
  });

  test(
    'reads binary and malformed UTF-8 content and closes each file',
    () async {
      client.file = _FakeSftpFile(
        chunks: [
          Uint8List.fromList([0x66, 0x6f]),
          Uint8List.fromList([0x80]),
        ],
      );

      expect(await service.readFileString('/remote/file.txt'), 'fo�');
      expect(client.file.closed, isTrue);
      expect(client.openedPaths.single.$1, '/remote/file.txt');
    },
  );

  test('reads only the head of a file and closes it', () async {
    client.file = _FakeSftpFile(
      chunks: [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6]),
      ],
    );

    final head = await service.readFileHead('/remote/big.bin', maxBytes: 4);

    expect(head, Uint8List.fromList([1, 2, 3, 4]));
    expect(client.file.closed, isTrue);
  });

  test('writes UTF-8 content with create, write, and truncate flags', () async {
    await service.writeStringToFile('/remote/file.txt', 'zażółć');

    final expectedMode =
        SftpFileOpenMode.create.flag |
        SftpFileOpenMode.write.flag |
        SftpFileOpenMode.truncate.flag;
    expect(client.openedPaths.single.$2, expectedMode);
    final tempPath = client.openedPaths.single.$1;
    expect(tempPath, startsWith('/remote/file.txt.tmp'));
    expect(client.file.writes.single.$1, 0);
    expect(
      client.file.writes.single.$2,
      Uint8List.fromList(utf8.encode('zażółć')),
    );
    expect(client.file.closed, isTrue);
    expect(client.renames, [(tempPath, '/remote/file.txt')]);
  });

  test('downloads chunks to disk and reports proportional progress', () async {
    final directory = await Directory.systemTemp.createTemp('termphin-sftp-');
    addTearDown(() => directory.delete(recursive: true));
    final target = '${directory.path}/download.bin';
    client.statResult = SftpFileAttrs(size: 4);
    client.file = _FakeSftpFile(
      chunks: [
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3, 4]),
      ],
    );
    final progress = <(int, int?)>[];

    await service.downloadFile(
      '/remote/download.bin',
      target,
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(await File(target).readAsBytes(), [1, 2, 3, 4]);
    expect(progress.last, (4, 4));
    expect(client.file.closed, isTrue);
  });

  test('stops a download the moment the transfer is cancelled', () async {
    final directory = await Directory.systemTemp.createTemp('termphin-sftp-');
    addTearDown(() => directory.delete(recursive: true));
    final target = '${directory.path}/download.bin';
    client.statResult = SftpFileAttrs(size: 300);
    client.file = _FakeSftpFile(
      chunks: List.generate(300, (_) => Uint8List.fromList([0])),
    );
    final cancel = CancelToken();
    var received = 0;

    await expectLater(
      service.downloadFile(
        '/remote/download.bin',
        target,
        cancel: cancel,
        onProgress: (bytes, _) {
          received = bytes;
          cancel.cancel();
        },
      ),
      throwsA(isA<TransferCancelled>()),
    );

    expect(received, lessThan(300));
    expect(await File(target).exists(), isFalse);
    expect(client.file.closed, isTrue);
  });

  test('a local write that cannot open reports instead of hanging', () async {
    final directory = await Directory.systemTemp.createTemp('termphin-sftp-');
    addTearDown(() => directory.delete(recursive: true));
    client.statResult = SftpFileAttrs(size: 4);
    client.file = _FakeSftpFile(
      chunks: [
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3, 4]),
      ],
    );

    await expectLater(
      service
          .downloadFile(
            '/remote/download.bin',
            '${directory.path}/missing/download.bin',
          )
          .timeout(const Duration(seconds: 10)),
      throwsA(
        predicate(
          (Object error) =>
              error.toString().contains('sftp.errors.localWriteError'),
        ),
      ),
    );
    expect(client.file.closed, isTrue);
  });

  test('reads a file the server reports no size for', () async {
    final directory = await Directory.systemTemp.createTemp('termphin-sftp-');
    addTearDown(() => directory.delete(recursive: true));
    final target = '${directory.path}/status';
    client.statResult = SftpFileAttrs(size: 0);
    client.file = _FakeSftpFile(
      chunks: [
        Uint8List.fromList([65, 66, 67]),
      ],
    );

    await service.downloadFile('/proc/self/status', target);

    expect(await File(target).readAsBytes(), [65, 66, 67]);
  });

  test('refuses to start a download on an already cancelled token', () async {
    final directory = await Directory.systemTemp.createTemp('termphin-sftp-');
    addTearDown(() => directory.delete(recursive: true));

    await expectLater(
      service.downloadFile(
        '/remote/download.bin',
        '${directory.path}/download.bin',
        cancel: CancelToken()..cancel(),
      ),
      throwsA(isA<TransferCancelled>()),
    );
    expect(client.openedPaths, isEmpty);
  });

  test(
    'throttles progress when chunks arrive faster than a frame renders',
    () async {
      final directory = await Directory.systemTemp.createTemp('termphin-sftp-');
      addTearDown(() => directory.delete(recursive: true));
      final target = '${directory.path}/download.bin';
      const chunkCount = 200;
      client.statResult = SftpFileAttrs(size: chunkCount);
      client.file = _FakeSftpFile(
        chunks: List.generate(chunkCount, (_) => Uint8List.fromList([0])),
      );
      final progress = <int>[];

      await service.downloadFile(
        '/remote/download.bin',
        target,
        onProgress: (received, _) => progress.add(received),
      );

      expect(progress.length, lessThan(chunkCount));
      expect(progress.first, greaterThan(0));
      expect(progress.last, chunkCount);
    },
  );

  test('uploads local bytes and reports completion', () async {
    final directory = await Directory.systemTemp.createTemp('termphin-sftp-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/upload.bin');
    await source.writeAsBytes([1, 2, 3, 4]);
    final progress = <(int, int?)>[];

    await service.uploadFile(
      source.path,
      '/remote/upload.bin',
      onProgress: (sent, total) => progress.add((sent, total)),
    );

    expect(client.file.writes.single.$1, 0);
    expect(client.file.writes.single.$2, [1, 2, 3, 4]);
    expect(progress, [(4, 4)]);
    expect(client.file.closed, isTrue);
  });

  test('uploads a stream of unknown size and reports what was sent', () async {
    final progress = <(int, int?)>[];

    await service.uploadStream(
      Stream.fromIterable([
        [1, 2],
        [3],
      ]),
      '/remote/shared.bin',
      onProgress: (sent, total) => progress.add((sent, total)),
    );

    expect(client.file.writes.single.$2, [1, 2, 3]);
    expect(progress.last, (3, null));
    expect(client.renames.single.$2, '/remote/shared.bin');
  });

  test('a source that fails mid-stream is an upload read error', () async {
    await expectLater(
      service.uploadStream(
        Stream<List<int>>.error(const FileSystemException('gone')),
        '/remote/shared.bin',
      ),
      _throwsSftpKey('sftp.errors.uploadReadError'),
    );
    expect(client.renames, isEmpty);
    expect(client.removedPaths, isNotEmpty);
  });

  test('maps SFTP status and transport failures to translation keys', () async {
    final cases = <(Object, String)>[
      (
        SftpStatusError(SftpStatusCode.noSuchFile, 'missing'),
        'sftp.errors.notFound',
      ),
      (
        SftpStatusError(SftpStatusCode.permissionDenied, 'denied'),
        'sftp.errors.permissionDenied',
      ),
      (
        SftpStatusError(SftpStatusCode.failure, 'File lock active'),
        'sftp.errors.fileLocked',
      ),
      (SftpAbortError('closed'), 'sftp.errors.connectionLost'),
      (SftpError('failure'), 'sftp.errors.failure'),
      (const SocketException('offline'), 'sftp.errors.networkError'),
      (TimeoutException('slow'), 'sftp.errors.timeout'),
      (StateError('unexpected'), 'sftp.errors.generic'),
    ];

    for (final (error, key) in cases) {
      client.error = error;
      await expectLater(service.listDirectory('/remote'), _throwsSftpKey(key));
    }
  });

  test('maps missing local upload files to an upload read error', () async {
    await expectLater(
      service.uploadFile('/missing/source.bin', '/remote/upload.bin'),
      _throwsSftpKey('sftp.errors.uploadReadError'),
    );
  });

  test('closes remote files when reading or writing fails', () async {
    client.file = _FakeSftpFile(readError: StateError('read failed'));
    await expectLater(
      service.readFileBytes('/remote/file.txt'),
      _throwsSftpKey('sftp.errors.generic'),
    );
    expect(client.file.closed, isTrue);

    client.file = _FakeSftpFile(writeError: StateError('write failed'));
    await expectLater(
      service.writeStringToFile('/remote/file.txt', 'content'),
      _throwsSftpKey('sftp.errors.generic'),
    );
    expect(client.file.closed, isTrue);
  });

  group('recursive operations', () {
    late _TreeSftpClient tree;
    late SftpService treeService;

    SftpService serviceFor(_TreeSftpClient client) =>
        SftpService.test(_UnusedSshClient(), () async => client);

    setUp(() {
      tree = _TreeSftpClient({
        '/root': ['a.txt', 'sub', 'empty'],
        '/root/sub': ['b.txt', 'deep'],
        '/root/sub/deep': ['c.txt'],
        '/root/empty': [],
      });
      treeService = serviceFor(tree);
    });

    test('clears a directory tree depth first before removing it', () async {
      await treeService.deletePath('/root', isDirectory: true);

      expect(tree.removedPaths, [
        '/root/a.txt',
        '/root/sub/b.txt',
        '/root/sub/deep/c.txt',
      ]);
      expect(tree.removedDirectories, [
        '/root/sub/deep',
        '/root/sub',
        '/root/empty',
        '/root',
      ]);
      expect(tree.tree, isEmpty);
    });

    test('deletes a directory the listing called a file', () async {
      await treeService.deletePath('/root/sub', isDirectory: false);

      expect(tree.removedDirectories, contains('/root/sub'));
      expect(tree.tree.containsKey('/root/sub'), isFalse);
    });

    test('deletes a file the caller called a directory', () async {
      await treeService.deletePath('/root/a.txt', isDirectory: true);

      expect(tree.removedPaths, ['/root/a.txt']);
    });

    test('treats an already deleted entry as success', () async {
      await treeService.deletePath('/root/gone.txt', isDirectory: false);

      expect(tree.removedPaths, isEmpty);
    });

    test('unlinks symlinks instead of following them', () async {
      final linked = _TreeSftpClient(
        {
          '/root': ['link', 'file.txt'],
          '/elsewhere': ['precious.txt'],
        },
        symlinks: {'/root/link': true},
      );

      await serviceFor(linked).deletePath('/root', isDirectory: true);

      expect(
        linked.removedPaths,
        containsAll(['/root/link', '/root/file.txt']),
      );
      expect(linked.tree.containsKey('/elsewhere'), isTrue);
    });

    test('walks a tree into paths relative to its root', () async {
      final entries = await treeService.walkDirectory('/root');

      expect(entries.where((e) => !e.isDirectory).map((e) => e.relativePath), [
        'a.txt',
        'sub/b.txt',
        'sub/deep/c.txt',
      ]);
      expect(entries.where((e) => e.isDirectory).map((e) => e.relativePath), [
        'sub',
        'empty',
        'sub/deep',
      ]);
      expect(
        entries.firstWhere((e) => e.relativePath == 'sub/b.txt').remotePath,
        '/root/sub/b.txt',
      );
    });

    test('skips symlinked directories while walking', () async {
      final linked = _TreeSftpClient(
        {
          '/root': ['link', 'file.txt'],
          '/root/link': ['loop.txt'],
        },
        symlinks: {'/root/link': true},
      );

      final entries = await serviceFor(linked).walkDirectory('/root');

      expect(entries.map((e) => e.relativePath), ['file.txt']);
    });
  });

  group('reconnect', () {
    test(
      'a closed SSH connection reads as lost and reopens the channel',
      () async {
        await service.stat('/remote/a');
        client.error = SSHStateError('SSH connection closed');

        await expectLater(
          service.stat('/remote/b'),
          _throwsSftpKey('sftp.errors.connectionLost'),
        );

        client.error = null;
        await service.stat('/remote/c');
        expect(openCount, 2);
      },
    );

    test('follows the session onto the client of a reconnect', () async {
      final before = _ReconnectableSshClient(_FakeSftpClient());
      final after = _ReconnectableSshClient(_FakeSftpClient());
      var current = before;
      final resolving = SftpService.resolving(() async => current);

      await resolving.listDirectory('/remote');
      before
        ..closed = true
        ..sftpClient.error = SSHStateError('SSH connection closed');
      current = after;

      await resolving.listDirectory('/remote');
      expect(before.sftpClient.listedPaths, ['/remote']);
      expect(after.sftpClient.listedPaths, ['/remote']);
    });

    test('a session with no connection reads as lost', () async {
      final resolving = SftpService.resolving(
        () async => throw Exception('SSH session is not connected.'),
      );

      await expectLater(
        resolving.stat('/remote'),
        _throwsSftpKey('sftp.errors.connectionLost'),
      );
    });
  });
}
