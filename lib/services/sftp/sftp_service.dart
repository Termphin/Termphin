import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'cancel_token.dart';
import 'sftp_remote_ops.dart';

/// One entry found while walking a remote directory tree.
class SftpWalkEntry {
  const SftpWalkEntry({
    required this.remotePath,
    required this.relativePath,
    required this.isDirectory,
    this.size,
  });

  final String remotePath;

  /// Path relative to the directory the walk started at, using `/`.
  final String relativePath;
  final bool isDirectory;
  final int? size;
}

/// How much to read from a file the server reports no size for. `read()` with
/// no length asks for the size and stops at 0, so `/proc`, `/sys` and similar
/// virtual files - which report 0 but have contents - would otherwise download
/// as empty. Reading with an explicit length stops at EOF anyway, so this is
/// only the ceiling for a file that never ends, like a device node.
const _unknownSizeReadCap = 8 * 1024 * 1024;

/// How long a local flush or close may take before the write counts as failed.
/// Both hang outright on a sink that has already errored.
const _localWriteTimeout = Duration(seconds: 5);

/// A command the server ran and refused, carrying what it said. Its
/// `toString` is that message, so it reaches the user as written.
class RemoteCommandException implements Exception {
  const RemoteCommandException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SftpService {
  final Future<SSHClient> Function() _client;
  final Future<SftpClient> Function(SSHClient client) _openSftp;
  SftpClient? _sftp;

  /// The connection [_sftp] was opened on.
  SSHClient? _sftpOwner;

  SftpService(SSHClient client) : this.resolving(() async => client);

  /// Asks [client] for the connection before every operation, so a service
  /// that outlives a reconnect - an open file browser - moves onto the new
  /// connection instead of failing on the dead one for good.
  SftpService.resolving(Future<SSHClient> Function() client)
    : _client = client,
      _openSftp = ((client) => client.sftp());

  @visibleForTesting
  SftpService.test(SSHClient client, Future<SftpClient> Function() openSftp)
    : _client = (() async => client),
      _openSftp = ((_) => openSftp());

  Future<void> init() async {
    final SSHClient client;
    try {
      client = await _client();
    } catch (_) {
      throw Exception('sftp.errors.connectionLost');
    }
    if (_sftp != null && identical(_sftpOwner, client)) return;
    if (_sftp != null) _invalidate();
    try {
      _sftp = await _openSftp(client);
      _sftpOwner = client;
    } on SSHChannelOpenError {
      throw Exception('sftp.errors.connectionLost');
    } on SocketException {
      throw Exception('sftp.errors.networkError');
    } on TimeoutException {
      throw Exception('sftp.errors.timeout');
    } catch (error) {
      throw _mapError(error);
    }
  }

  /// Closes the SFTP channel. Each [SftpService] opens its own, and sshd caps
  /// channels per connection (MaxSessions, 10 by default) - one left open per
  /// upload or browser visit starves the connection until every new one is
  /// refused. A later call opens a fresh channel.
  Future<void> close() async {
    final open = _sftp;
    _sftp = null;
    try {
      await open?.close();
    } catch (_) {}
  }

  /// Drops the cached SFTP session so the next operation reopens it. Called
  /// when an operation reveals the underlying channel is dead (e.g. after an
  /// SSH reconnect), since [_sftp] otherwise stays a live-looking but
  /// unusable handle forever.
  void _invalidate() {
    _sftp = null;
    _sftpOwner = null;
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      await init();
      return await body();
    } catch (error) {
      final mapped = _mapError(error);
      if (_isConnectionError(error)) _invalidate();
      throw mapped;
    }
  }

  bool _isConnectionError(Object error) {
    if (error is SftpAbortError) return true;
    if (error is SSHSocketError || error is SSHChannelOpenError) return true;
    if (error is SSHStateError) return true;
    if (error is SocketException) return true;
    if (error is SftpStatusError) {
      return error.code == SftpStatusCode.connectionLost ||
          error.code == SftpStatusCode.noConnection;
    }
    return false;
  }

  SftpClient get sftp {
    if (_sftp == null) throw Exception('sftp.errors.connectionLost');
    return _sftp!;
  }

  Future<List<SftpName>> listDirectory(String path) {
    return _guard(() => sftp.listdir(path));
  }

  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) {
    return _guard(() => sftp.stat(path, followLink: followLink));
  }

  Future<void> createDirectory(String path) {
    return _guard(() => sftp.mkdir(path));
  }

  Future<void> createEmptyFile(String path) {
    return _guard(() async {
      final file = await sftp.open(
        path,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.exclusive,
      );
      await file.close();
    });
  }

  /// Whether something is at [path]. Only a "no such file" counts as absent:
  /// a stat this account may not perform says nothing about what is there, and
  /// the one caller uses this to decide whether to ask before overwriting -
  /// where guessing "nothing there" is the answer that loses a file.
  Future<bool> exists(String path) async {
    try {
      await stat(path, followLink: false);
      return true;
    } catch (error) {
      return !error.toString().contains('sftp.errors.notFound');
    }
  }

  /// Streams [remotePath] into [localPath], reporting bytes rather than a
  /// fraction so the caller can show sizes and a transfer rate. [onProgress]
  /// gets a null total when the server did not say how big the file is.
  ///
  /// A cancelled transfer stops at once - mid-chunk, even on a link that has
  /// gone quiet - and leaves no partial file behind.
  ///
  /// Chunks go through a [StreamController] and `addStream` rather than
  /// straight into [IOSink.add]: a sink whose open or write failed (a full
  /// disk, an ejected card, a revoked SAF grant) reports that on the future
  /// `addStream` returns, while `add` routes it to the top-level zone as an
  /// uncaught crash and leaves `flush`/`close` hanging for good. That same
  /// write failure is passed to [_drain] as `failure`, so a failed sink stops
  /// the drain reading more of the remote file into the (now stuck) buffer.
  /// Progress is throttled to about 12 reports a second, since a fast link
  /// delivers chunks far quicker than a frame renders. The buffer's own close
  /// is not awaited - once `addStream` has failed its subscription is gone,
  /// and closing a controller nothing is listening to never completes;
  /// awaiting `pump` afterwards is what actually surfaces whether the write
  /// finished. A sink close is bounded too, since a close on an already-failed
  /// sink hangs the same way a write does. [FileSystemException] is not
  /// always mapped to a generic write error: a full disk has its own, more
  /// useful message.
  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    void Function(int received, int? total)? onProgress,
    CancelToken? cancel,
  }) async {
    await _guard(() async {
      cancel?.throwIfCancelled();
      final file = await sftp.open(remotePath);
      IOSink? sink;
      var completed = false;
      try {
        final fileStat = await sftp.stat(remotePath);
        final totalSize = (fileStat.size ?? 0) > 0 ? fileStat.size : null;

        sink = File(localPath).openWrite();
        final buffer = StreamController<Uint8List>();
        final pump = sink.addStream(buffer.stream);
        final writeFailure = Completer<Object>();
        unawaited(
          pump.then(
            (_) {},
            onError: (Object error) {
              if (!writeFailure.isCompleted) writeFailure.complete(error);
            },
          ),
        );

        var received = 0;
        var lastReported = DateTime.fromMillisecondsSinceEpoch(0);
        try {
          await _drain(
            file.read(length: totalSize == null ? _unknownSizeReadCap : null),
            cancel: cancel,
            failure: writeFailure.future,
            onChunk: (chunk) {
              buffer.add(chunk);
              received += chunk.length;
              final now = DateTime.now();
              if (now.difference(lastReported) >=
                  const Duration(milliseconds: 80)) {
                lastReported = now;
                onProgress?.call(received, totalSize);
              }
            },
          );
        } finally {
          unawaited(buffer.close().catchError((_) {}));
        }
        await pump;
        onProgress?.call(received, totalSize ?? received);
        await _bounded(sink.flush());
        completed = true;
      } on FileSystemException catch (error) {
        throw _mapError(error);
      } finally {
        try {
          final closing = sink?.close();
          if (closing != null) await _bounded(closing);
        } catch (_) {
        } finally {
          try {
            await file.close();
          } catch (_) {}
        }
        if (!completed) await _deleteQuietly(localPath);
      }
    });
  }

  /// Pumps [source] into [onChunk] and stops the moment [cancel] fires,
  /// instead of at the next chunk - a transfer that has stalled would
  /// otherwise ignore Cancel for as long as the server stays silent.
  ///
  /// [failure] does the same for an error raised somewhere other than the
  /// stream - the local sink's, which surfaces on its own future.
  ///
  /// Pauses the subscription for a frame every few chunks, so the reader
  /// does not run ahead of the UI while it paints.
  Future<void> _drain(
    Stream<Uint8List> source, {
    required void Function(Uint8List chunk) onChunk,
    CancelToken? cancel,
    Future<Object>? failure,
  }) async {
    final done = Completer<void>();
    var chunkCount = 0;
    late final StreamSubscription<Uint8List> subscription;
    subscription = source.listen(
      (chunk) {
        try {
          onChunk(chunk);
        } catch (error, stack) {
          if (!done.isCompleted) done.completeError(error, stack);
          return;
        }
        if (++chunkCount % 8 == 0) {
          subscription.pause(Future<void>.delayed(Duration.zero));
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    unawaited(
      cancel?.whenCancelled.then((_) {
        if (!done.isCompleted) done.completeError(const TransferCancelled());
      }),
    );
    unawaited(
      failure?.then((error) {
        if (!done.isCompleted) done.completeError(error);
      }),
    );
    try {
      await done.future;
    } finally {
      await subscription.cancel();
    }
  }

  /// Waits [_localWriteTimeout] for a local sink operation. Timing one out
  /// abandons it, and an abandoned future that fails later has no listener
  /// left - which reaches the top-level zone as a crash - so its error is
  /// claimed here as well.
  Future<void> _bounded(Future<void> operation) {
    unawaited(operation.catchError((_) {}));
    return operation.timeout(_localWriteTimeout);
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Reads a small remote text file whole, trimmed - built for the agent's
  /// own tiny state files (`cwd`, `boot_id`), not general-purpose downloads.
  /// Bails past a few KB rather than trusting an arbitrary remote path to
  /// stay small.
  Future<String> readSmallTextFile(String path) {
    return _guard(() async {
      final file = await sftp.open(path);
      try {
        final bytes = <int>[];
        await for (final chunk in file.read()) {
          bytes.addAll(chunk);
          if (bytes.length > 8192) break;
        }
        return utf8.decode(bytes, allowMalformed: true).trim();
      } finally {
        await file.close();
      }
    });
  }

  Future<void> uploadFile(
    String localPath,
    String remotePath, {
    void Function(int sent, int? total)? onProgress,
    CancelToken? cancel,
  }) async {
    final localFile = File(localPath);
    final int totalSize;
    try {
      totalSize = await localFile.length();
    } on FileSystemException {
      throw Exception('sftp.errors.uploadReadError');
    }
    await uploadStream(
      localFile.openRead(),
      remotePath,
      totalSize: totalSize,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  /// Writes [source] to [remotePath] through a temporary name, so a failed or
  /// cancelled upload never leaves half a file where the real one was.
  /// [totalSize] is only for progress and may be unknown. A
  /// [FileSystemException] from [source] reads as the local side failing.
  ///
  /// `SftpFile.writeBytes` already pipelines one call's data as parallel 16KB
  /// packets, but `File.openRead()` only ever hands over ~64KB at a time -
  /// awaiting one call before reading the next capped the in-flight window
  /// (and so throughput) at that 64KB, which read as a hard ~1MB/s ceiling on
  /// any link with real round-trip time. Batching several stream chunks into
  /// one bigger write before awaiting it widens that window without any
  /// manual pipelining of our own. With no total size to reach, a final
  /// progress call is forced at the end, since the throttled one may be up
  /// to 80ms stale.
  Future<void> uploadStream(
    Stream<List<int>> source,
    String remotePath, {
    int? totalSize,
    void Function(int sent, int? total)? onProgress,
    CancelToken? cancel,
  }) async {
    final known = totalSize != null && totalSize > 0 ? totalSize : null;
    await _guard(() async {
      cancel?.throwIfCancelled();
      final tempRemotePath =
          '$remotePath.tmp${DateTime.now().microsecondsSinceEpoch}';
      final file = await sftp.open(
        tempRemotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      var succeeded = false;
      try {
        final stream = source;

        const writeBatchSize = 1024 * 1024;
        final batch = BytesBuilder(copy: false);

        int uploaded = 0;
        var lastReported = DateTime.fromMillisecondsSinceEpoch(0);

        Future<void> flush() async {
          if (batch.isEmpty) return;
          final data = batch.takeBytes();
          final write = file.writeBytes(data, offset: uploaded);
          await (cancel == null ? write : cancel.race(write));
          uploaded += data.length;
          final now = DateTime.now();
          if ((known != null && uploaded >= known) ||
              now.difference(lastReported) >=
                  const Duration(milliseconds: 80)) {
            lastReported = now;
            onProgress?.call(uploaded, known);
          }
        }

        try {
          await for (final chunk in stream) {
            cancel?.throwIfCancelled();
            batch.add(chunk);
            if (batch.length >= writeBatchSize) await flush();
          }
          await flush();
          if (known == null) onProgress?.call(uploaded, null);
        } on FileSystemException {
          throw Exception('sftp.errors.uploadReadError');
        }
        await file.close();
        await sftp.rename(tempRemotePath, remotePath);
        succeeded = true;
      } finally {
        if (!succeeded) {
          try {
            await file.close();
          } catch (_) {}
          try {
            await sftp.remove(tempRemotePath);
          } catch (_) {}
        }
      }
    });
  }

  Future<void> deletePath(String remotePath, {bool isDirectory = false}) {
    return _guard(() => _deleteEntry(remotePath, isDirectory: isDirectory));
  }

  /// [isDirectory] is only a hint: a listing can mislabel an entry (symlinks,
  /// servers that answer with sparse attributes), so the real type is checked
  /// whenever the first attempt fails.
  Future<void> _deleteEntry(String path, {required bool isDirectory}) async {
    if (!isDirectory) {
      try {
        await sftp.remove(path);
        return;
      } on SftpStatusError catch (error) {
        if (error.code == SftpStatusCode.noSuchFile) return;
        final attrs = await _lstatOrNull(path);
        if (attrs == null) return;
        if (!attrs.isDirectory) rethrow;
      }
    }
    await _deleteDirectoryRecursive(path);
  }

  Future<SftpFileAttrs?> _lstatOrNull(String path) async {
    try {
      return await sftp.stat(path, followLink: false);
    } catch (_) {
      return null;
    }
  }

  String _childPath(String parent, String name) =>
      parent.endsWith('/') ? '$parent$name' : '$parent/$name';

  /// Empties and removes [path]. An empty directory goes in one `rmdir`
  /// call; anything else falls through to clearing it out first. If the
  /// caller said directory but the server disagrees, a plain remove is
  /// tried before reporting the listing failure - which is the real story
  /// if that second attempt fails too, so it is what gets rethrown. A
  /// symlink child is unlinked, never followed, since deleting through one
  /// would wipe a directory the user never selected.
  Future<void> _deleteDirectoryRecursive(String path) async {
    try {
      await sftp.rmdir(path);
      return;
    } on SftpStatusError catch (error) {
      if (error.code == SftpStatusCode.noSuchFile) return;
      if (error.code != SftpStatusCode.failure) rethrow;
    }

    final List<SftpName> entries;
    try {
      entries = await sftp.listdir(path);
    } catch (_) {
      try {
        await sftp.remove(path);
        return;
      } catch (_) {}
      rethrow;
    }
    var processed = 0;
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      final childPath = _childPath(path, entry.filename);
      final isChildDirectory =
          entry.attr.isDirectory && !entry.attr.isSymbolicLink;
      await _deleteEntry(childPath, isDirectory: isChildDirectory);
      if (++processed % 16 == 0) await Future<void>.delayed(Duration.zero);
    }

    await sftp.rmdir(path);
  }

  /// Every file and directory under [path], depth first, with paths relative
  /// to it. Symlinked directories are listed but not descended into, so a
  /// loop cannot hang the walk - a symlink is followed once to see what it
  /// points at, and a link to a directory is skipped rather than copied
  /// recursively.
  ///
  /// A directory with thousands of children is one `listdir` call, so
  /// reporting only per directory can look stuck; the count is published as
  /// entries land, throttled to what a frame can show.
  Future<List<SftpWalkEntry>> walkDirectory(
    String path, {
    void Function(int found)? onProgress,
    CancelToken? cancel,
  }) {
    return _guard(() async {
      final entries = <SftpWalkEntry>[];
      final queue = <(String, String)>[(path, '')];
      final visited = <String>{};

      var lastReported = DateTime.fromMillisecondsSinceEpoch(0);
      void report() {
        final now = DateTime.now();
        if (now.difference(lastReported) < const Duration(milliseconds: 80)) {
          return;
        }
        lastReported = now;
        onProgress?.call(entries.length);
      }

      while (queue.isNotEmpty) {
        cancel?.throwIfCancelled();
        report();
        final (directory, relative) = queue.removeAt(0);
        if (!visited.add(directory)) continue;
        final children = await sftp.listdir(directory);
        for (final child in children) {
          if (child.filename == '.' || child.filename == '..') continue;
          final childPath = _childPath(directory, child.filename);
          final childRelative = relative.isEmpty
              ? child.filename
              : '$relative/${child.filename}';
          final isDirectory =
              child.attr.isDirectory && !child.attr.isSymbolicLink;
          if (child.attr.isSymbolicLink && !child.attr.isDirectory) {
            final target = await _statOrNull(childPath);
            if (target?.isDirectory ?? false) continue;
          }
          entries.add(
            SftpWalkEntry(
              remotePath: childPath,
              relativePath: childRelative,
              isDirectory: isDirectory,
              size: child.attr.size,
            ),
          );
          if (isDirectory) queue.add((childPath, childRelative));
          report();
        }
        await Future<void>.delayed(Duration.zero);
      }
      onProgress?.call(entries.length);
      return entries;
    });
  }

  Future<SftpFileAttrs?> _statOrNull(String path) async {
    try {
      return await sftp.stat(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> rename(String oldPath, String newPath) {
    return _guard(() => sftp.rename(oldPath, newPath));
  }

  Future<bool>? _commandsAvailable;
  bool? _commandsKnown;

  /// False once this server has shown it runs no commands - an account locked
  /// to SFTP. Null until something has asked.
  bool? get canRunCommands => _commandsKnown;

  /// Copies [from] to [to] on the server; nothing passes through the device.
  /// [to] must not exist yet, or a folder lands inside it.
  Future<void> copyEntry(String from, String to) {
    return _guard(() => _runFileCommand(copyCommand(from, to), from));
  }

  /// A rename, which is instant; across filesystems the server refuses one,
  /// and `mv` does the copy and delete there instead.
  Future<void> moveEntry(String from, String to) {
    return _guard(() async {
      try {
        await sftp.rename(from, to);
        return;
      } on SftpStatusError catch (error) {
        if (error.code != SftpStatusCode.failure &&
            error.code != SftpStatusCode.opUnsupported) {
          rethrow;
        }
      }
      await _runFileCommand(moveCommand(from, to), from);
    });
  }

  /// Removes whatever is at [path], file or folder, before a replace.
  Future<void> clearPath(String path) {
    return _guard(() async {
      final attrs = await _lstatOrNull(path);
      if (attrs == null) return;
      final isDirectory = attrs.isDirectory && !attrs.isSymbolicLink;
      await _deleteEntry(path, isDirectory: isDirectory);
    });
  }

  Future<void> _runFileCommand(String command, String anyPath) async {
    if (!await _probeCommands(anyPath)) {
      throw Exception('sftp.errors.noShell');
    }
    final result = await _exec(command);
    if (result.exitCode == 0) return;
    final said = result.stderr.trim().split('\n').first.trim();
    if (result.exitCode == null && said.isEmpty) return;
    throw RemoteCommandException(
      said.isNotEmpty ? said : 'exit ${result.exitCode}',
    );
  }

  /// Asked once per service. A failure to ask - the connection dropping -
  /// is not remembered as an answer.
  Future<bool> _probeCommands(String anyPath) {
    return _commandsAvailable ??= () async {
      try {
        final result = await _exec(
          execProbeCommand(anyPath),
        ).timeout(const Duration(seconds: 10));
        final available = result.stdout.contains(execProbeMarker);
        _commandsKnown = available;
        return available;
      } on TimeoutException {
        _commandsKnown = false;
        return false;
      } catch (_) {
        _commandsAvailable = null;
        rethrow;
      }
    }();
  }

  /// `runWithResult` leaves stdin open, and an account forced to
  /// `internal-sftp` then waits on it for an SFTP handshake forever. Closing
  /// it at once lets that exit.
  Future<({int? exitCode, String stdout, String stderr})> _exec(
    String command,
  ) async {
    final session = await (await _client()).execute(command);
    unawaited(session.stdin.close().catchError((_) {}));
    final out = session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
    final err = session.stderr.fold<List<int>>([], (a, b) => a..addAll(b));
    final (stdout, stderr) = await (out, err).wait;
    await session.done;
    return (
      exitCode: session.exitCode,
      stdout: utf8.decode(stdout, allowMalformed: true),
      stderr: utf8.decode(stderr, allowMalformed: true),
    );
  }

  Future<Uint8List> readFileBytes(String remotePath) {
    return _guard(() async {
      final size = (await sftp.stat(remotePath)).size ?? 0;
      final file = await sftp.open(remotePath);
      try {
        final builder = BytesBuilder(copy: false);
        int chunkCount = 0;
        await for (final chunk in file.read(
          length: size > 0 ? null : _unknownSizeReadCap,
        )) {
          builder.add(chunk);
          if (++chunkCount % 8 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        return builder.takeBytes();
      } finally {
        await file.close();
      }
    });
  }

  /// Reads at most [maxBytes] from the start of [remotePath] - enough to tell
  /// what a file is without pulling the whole thing over the wire.
  Future<Uint8List> readFileHead(String remotePath, {int maxBytes = 8 * 1024}) {
    return _guard(() async {
      final file = await sftp.open(remotePath);
      try {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in file.read(length: maxBytes)) {
          builder.add(chunk);
          if (builder.length >= maxBytes) break;
        }
        final bytes = builder.takeBytes();
        return bytes.length > maxBytes
            ? Uint8List.sublistView(bytes, 0, maxBytes)
            : bytes;
      } finally {
        await file.close();
      }
    });
  }

  Future<String> readFileString(String remotePath) async {
    final bytes = await readFileBytes(remotePath);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> writeStringToFile(String remotePath, String content) {
    return _guard(() async {
      final tempRemotePath =
          '$remotePath.tmp${DateTime.now().microsecondsSinceEpoch}';
      final file = await sftp.open(
        tempRemotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      var succeeded = false;
      try {
        final bytes = utf8.encode(content);
        await file.writeBytes(Uint8List.fromList(bytes));
        await file.close();
        await sftp.rename(tempRemotePath, remotePath);
        succeeded = true;
      } finally {
        if (!succeeded) {
          try {
            await file.close();
          } catch (_) {}
          try {
            await sftp.remove(tempRemotePath);
          } catch (_) {}
        }
      }
    });
  }

  /// Maps a raw I/O or SFTP exception to one of the `sftp.errors.*` keys the
  /// UI knows how to show.
  ///
  /// For a [FileSystemException] the reason lives on `osError` ("No space
  /// left on device", errno 28); `message` is only ever the operation that
  /// failed ("writeFrom failed").
  Exception _mapError(Object error) {
    if (error is RemoteCommandException) return error;
    if (error is Exception) {
      final msg = error.toString();
      if (msg.startsWith('Exception: sftp.errors.')) return error;
    }
    if (error is SftpStatusError) {
      return Exception(_mapSftpStatus(error.code, error.message));
    }
    if (error is SftpAbortError || error is SSHStateError) {
      return Exception('sftp.errors.connectionLost');
    }
    if (error is SftpError) {
      return Exception('sftp.errors.failure');
    }
    if (error is SSHSocketError || error is SSHChannelOpenError) {
      return Exception('sftp.errors.networkError');
    }
    if (error is FileSystemException) {
      const noSpaceErrno = 28;
      final osError = error.osError;
      if (osError?.errorCode == noSpaceErrno ||
          (osError?.message ?? error.message).contains('No space left')) {
        return Exception('sftp.errors.diskFull');
      }
      return Exception('sftp.errors.localWriteError');
    }
    if (error is SocketException) {
      return Exception('sftp.errors.networkError');
    }
    if (error is TimeoutException) {
      return Exception('sftp.errors.timeout');
    }
    return Exception('sftp.errors.generic');
  }

  String _mapSftpStatus(int code, String message) {
    return switch (code) {
      SftpStatusCode.noSuchFile => 'sftp.errors.notFound',
      SftpStatusCode.permissionDenied => 'sftp.errors.permissionDenied',
      SftpStatusCode.connectionLost => 'sftp.errors.connectionLost',
      SftpStatusCode.noConnection => 'sftp.errors.networkError',
      SftpStatusCode.failure =>
        message.toLowerCase().contains('lock')
            ? 'sftp.errors.fileLocked'
            : 'sftp.errors.failure',
      _ => 'sftp.errors.failure',
    };
  }
}
