import 'dart:io' show FileSystemException;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../sftp/upload_plan.dart' show LocalUpload;

/// What another app shared: the files in it, read from that app as they
/// upload. Text is not taken - there is no terminal here to type it into -
/// but whether there was any is kept, so a share of text alone can say why
/// nothing happens instead of reading as files that failed to open.
class SharedContent {
  const SharedContent(this.files, {this.hadText = false});

  final List<LocalUpload> files;
  final bool hadText;

  /// The native side's answer to `takeShare`, or null for no share at all.
  /// Files that could not be opened leave an empty list, which is still a
  /// share - one to say something about. [read] fetches the next chunk of a
  /// file, null once it is all read; [rewind] puts it back to the start.
  static SharedContent? fromChannel(
    Map<Object?, Object?>? raw, {
    required Future<Uint8List?> Function(String id) read,
    required Future<void> Function(String id) rewind,
  }) {
    if (raw == null) return null;
    final files = raw['files'];
    if (files is! List<Object?>) return null;
    return SharedContent([
      for (final entry in files)
        if (entry case {'id': final String id, 'name': final String name})
          LocalUpload(
            name: name,
            open: () => _chunks(id, read, rewind),
            length: () async => entry['size'] as int?,
          ),
    ], hadText: raw['text'] == true);
  }

  /// Starts from the first byte every time: an upload that failed, or went to
  /// another machine, reads the file again rather than its unread tail. A
  /// platform failure reads as the local side failing, like a file that
  /// went away.
  static Stream<List<int>> _chunks(
    String id,
    Future<Uint8List?> Function(String id) read,
    Future<void> Function(String id) rewind,
  ) async* {
    try {
      await rewind(id);
      while (true) {
        final chunk = await read(id);
        if (chunk == null) return;
        yield chunk;
      }
    } on PlatformException catch (error) {
      throw FileSystemException(error.message ?? 'shared file unreadable');
    }
  }
}

/// The share `ShareActivity` was opened with, and the way back out of it.
///
/// That activity runs its own engine on `shareMain`, so this is only ever
/// called there - the main app has no share to take.
class ShareIntentService {
  ShareIntentService._();
  static final ShareIntentService instance = ShareIntentService._();

  static const _channel = MethodChannel('dev.termphin.termphin/share');

  /// What was shared, or null when there is nothing to read it from.
  Future<SharedContent?> take() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'takeShare',
      );
      return SharedContent.fromChannel(raw, read: _read, rewind: _rewind);
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// A megabyte at a time: far above what SSH moves on a phone, small
  /// enough that nothing piles up while the upload waits on the network.
  static const _chunkSize = 1 << 20;

  static Future<Uint8List?> _read(String id) =>
      _channel.invokeMethod<Uint8List>('read', {'id': id, 'max': _chunkSize});

  static Future<void> _rewind(String id) =>
      _channel.invokeMethod<void>('rewind', {'id': id});

  /// Closes the share screen, which leaves the sharing app in front.
  Future<void> finish() async {
    try {
      await _channel.invokeMethod<void>('finish');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  @visibleForTesting
  static const channel = _channel;
}
