import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/strings.g.dart';
import '../../utils/platform_info.dart';
import '../platform/ios_background_task.dart';
import '../platform/local_notifications_service.dart';
import 'cancel_token.dart';
import 'download_location.dart';
import 'sftp_service.dart';

/// What ended up in the Downloads folder, so the caller can say so and offer
/// to open it.
class SavedDownload {
  const SavedDownload({required this.fileName, this.uri, this.fileCount = 1});

  final String fileName;

  /// Content URI of the saved file, when the platform handed one back.
  final String? uri;

  /// How many files were written (more than one for a folder, or for a
  /// selection of several entries).
  final int fileCount;
}

/// What a transfer is busy with. Listing a big folder happens before any byte
/// moves and can take a while; saying so is the difference between "working"
/// and "hung".
enum TransferPhase { scanning, transferring }

/// How far along a transfer is. [bytes] counts the whole transfer, not the
/// file currently in flight, so it never jumps backwards and a rate computed
/// from it stays steady across a folder.
///
/// [totalBytes] and [fraction] are null when nothing knows the size up front,
/// which is what a server reporting no sizes leaves the transfer with.
class TransferProgress {
  const TransferProgress({
    required this.label,
    this.phase = TransferPhase.transferring,
    this.itemIndex = 1,
    this.itemCount = 1,
    this.bytes = 0,
    this.totalBytes,
    this.fraction,
  });

  final TransferPhase phase;

  /// Name of the file being transferred right now.
  final String label;

  /// 1-based position in a multi-item transfer.
  final int itemIndex;
  final int itemCount;

  final int bytes;
  final int? totalBytes;

  /// 0..1 across everything, or null while it cannot be known.
  final double? fraction;
}

typedef TransferProgressCallback = void Function(TransferProgress progress);

/// One entry the user picked out of a listing.
class SftpEntryRef {
  const SftpEntryRef({
    required this.name,
    required this.isDirectory,
    this.size,
  });

  final String name;
  final bool isDirectory;
  final int? size;
}

class DownloadService {
  static const _channel = MethodChannel('dev.termphin.termphin/downloads');
  static final _rng = Random();
  static final Map<int, CancelToken> _activeDownloads = {};
  static bool _handlerInitialized = false;

  static void _ensureMethodCallHandler() {
    if (_handlerInitialized) return;
    _handlerInitialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'downloadCancelRequested') {
        final args = call.arguments;
        final id = args is int ? args : (args as Map?)?['id'] as int?;
        if (id != null) {
          _activeDownloads[id]?.cancel();
        }
      }
    });
  }

  /// Opens a previously saved download in whatever app handles it. A desktop
  /// has no share sheet worth the name, so there the file opens in whatever
  /// the system associates with it, as a double click would.
  static Future<void> openSavedDownload(
    SavedDownload download, {
    Rect? sharePositionOrigin,
  }) async {
    final uri = download.uri;
    if (uri == null) return;
    if (isAndroidPlatform) {
      await _channel.invokeMethod('openDownload', {
        'uri': uri,
        'fileName': download.fileName,
      });
    } else if (isDesktopPlatform) {
      if (await File(uri).exists()) await launchUrl(Uri.file(uri));
    } else {
      if (await File(uri).exists()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(uri)],
            sharePositionOrigin: sharePositionOrigin,
          ),
        );
      }
    }
  }

  /// Shows a saved download in the system's file manager: its folder opens,
  /// which every desktop can do without knowing which file manager it runs.
  static Future<void> revealSavedDownload(SavedDownload download) async {
    final uri = download.uri;
    if (uri == null || !isDesktopPlatform) return;
    await launchUrl(Uri.directory(File(uri).parent.path));
  }

  static Future<SavedDownload> downloadSftpFile({
    required SftpService sftp,
    required String remotePath,
    required String fileName,
    TransferProgressCallback? onProgress,
    CancelToken? cancel,
  }) => IOSBackgroundTask.guard(
    'download',
    () => _downloadFile(
      sftp: sftp,
      remotePath: remotePath,
      fileName: fileName,
      onProgress: onProgress,
      cancel: cancel,
    ),
  );

  static Future<SavedDownload> _downloadFile({
    required SftpService sftp,
    required String remotePath,
    required String fileName,
    TransferProgressCallback? onProgress,
    CancelToken? cancel,
    bool announce = true,
  }) async {
    final effectiveCancel = cancel ?? CancelToken();
    final notification = await _DownloadNotification.start(
      fileName,
      cancel: effectiveCancel,
    );
    final tempDir = await getTemporaryDirectory();
    final localPath =
        '${tempDir.path}/download_${DateTime.now().microsecondsSinceEpoch}_'
        '${_sanitizeSegment(fileName)}';

    try {
      await sftp.downloadFile(
        remotePath,
        localPath,
        cancel: effectiveCancel,
        onProgress: (received, total) {
          onProgress?.call(
            TransferProgress(
              label: fileName,
              bytes: received,
              totalBytes: total,
              fraction: _fractionOf(received, total),
            ),
          );
          notification.report(_fractionOf(received, total));
        },
      );
      effectiveCancel.throwIfCancelled();

      final uri = await _save(sourcePath: localPath, fileName: fileName);
      await notification.complete(fileName, uri: uri, announce: announce);
      return SavedDownload(fileName: fileName, uri: uri);
    } catch (error) {
      await notification.dismiss(error, announce: announce);
      rethrow;
    } finally {
      _activeDownloads.remove(notification.id);
      await _deleteQuietly(localPath);
    }
  }

  /// Copies a folder into `Downloads/<folder>/…`, keeping its shape. The tree
  /// is listed first, which on a big folder is a long silence - hence the
  /// scanning phase, so the dialog says what it is waiting for.
  static Future<SavedDownload> downloadSftpDirectory({
    required SftpService sftp,
    required String remotePath,
    required String folderName,
    TransferProgressCallback? onProgress,
    CancelToken? cancel,
  }) => IOSBackgroundTask.guard(
    'download',
    () => _downloadDirectory(
      sftp: sftp,
      remotePath: remotePath,
      folderName: folderName,
      onProgress: onProgress,
      cancel: cancel,
    ),
  );

  static Future<SavedDownload> _downloadDirectory({
    required SftpService sftp,
    required String remotePath,
    required String folderName,
    TransferProgressCallback? onProgress,
    CancelToken? cancel,
    bool announce = true,
  }) async {
    final effectiveCancel = cancel ?? CancelToken();
    final notification = await _DownloadNotification.start(
      folderName,
      cancel: effectiveCancel,
    );
    try {
      final saved = await _copyTree(
        sftp: sftp,
        remotePath: remotePath,
        folderName: folderName,
        tempDir: await getTemporaryDirectory(),
        notification: notification,
        onProgress: onProgress,
        cancel: effectiveCancel,
      );
      await notification.complete(
        folderName,
        fileCount: saved.fileCount,
        uri: saved.uri,
        announce: announce,
      );
      return saved;
    } catch (error) {
      await notification.dismiss(error, announce: announce);
      rethrow;
    } finally {
      _activeDownloads.remove(notification.id);
    }
  }

  /// Downloads everything the user picked, one entry at a time, reporting the
  /// set as a single transfer.
  static Future<SavedDownload?> downloadSftpSelection({
    required SftpService sftp,
    required String parentPath,
    required List<SftpEntryRef> entries,
    required String multiFileLabel,
    TransferProgressCallback? onProgress,
    CancelToken? cancel,
  }) => IOSBackgroundTask.guard(
    'download',
    () => _downloadSelection(
      sftp: sftp,
      parentPath: parentPath,
      entries: entries,
      multiFileLabel: multiFileLabel,
      onProgress: onProgress,
      cancel: cancel,
    ),
  );

  /// Byte totals only mean anything when every entry announced one; a folder
  /// never does, so a mixed selection falls back to counting entries.
  static Future<SavedDownload?> _downloadSelection({
    required SftpService sftp,
    required String parentPath,
    required List<SftpEntryRef> entries,
    required String multiFileLabel,
    TransferProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    if (entries.isEmpty) return null;
    final effectiveCancel = cancel ?? CancelToken();

    final total = entries.length;
    final knownTotal = entries.every((e) => !e.isDirectory && e.size != null)
        ? entries.fold<int>(0, (sum, e) => sum + (e.size ?? 0))
        : null;
    var bytesBefore = 0;
    SavedDownload? lastSaved;
    var savedCount = 0;

    for (var index = 0; index < entries.length; index++) {
      effectiveCancel.throwIfCancelled();
      final entry = entries[index];
      final remotePath = _joinPath(parentPath, entry.name);
      var entryBytes = 0;

      void report(TransferProgress inner) {
        entryBytes = inner.bytes;
        final overall = bytesBefore + inner.bytes;
        onProgress?.call(
          TransferProgress(
            label: inner.label,
            phase: inner.phase,
            itemIndex: index + 1,
            itemCount: total,
            bytes: overall,
            totalBytes: knownTotal,
            fraction: knownTotal != null
                ? _fractionOf(overall, knownTotal)
                : ((index + (inner.fraction ?? 0)) / total).clamp(0.0, 1.0),
          ),
        );
      }

      try {
        lastSaved = entry.isDirectory
            ? await _downloadDirectory(
                sftp: sftp,
                remotePath: remotePath,
                folderName: entry.name,
                onProgress: report,
                cancel: effectiveCancel,
                announce: false,
              )
            : await _downloadFile(
                sftp: sftp,
                remotePath: remotePath,
                fileName: entry.name,
                onProgress: report,
                cancel: effectiveCancel,
                announce: false,
              );
      } catch (error) {
        if (error is! TransferCancelled) {
          await LocalNotificationsService.instance.showTransferFailed(
            fileName: multiFileLabel,
          );
        }
        rethrow;
      }
      bytesBefore += entryBytes;
      savedCount++;
    }

    if (lastSaved == null) return null;
    final saved = savedCount > 1
        ? SavedDownload(fileName: multiFileLabel, fileCount: savedCount)
        : lastSaved;
    await LocalNotificationsService.instance.showTransferComplete(
      fileName: saved.fileName,
      fileCount: saved.fileCount,
    );
    return saved;
  }

  /// Walks the tree and copies it file by file, keeping its shape under
  /// `Downloads/<folder>/…`. An empty tree still counts as done rather than
  /// as a failure the user has to interpret.
  static Future<SavedDownload> _copyTree({
    required SftpService sftp,
    required String remotePath,
    required String folderName,
    required Directory tempDir,
    required _DownloadNotification notification,
    TransferProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    final entries = await sftp.walkDirectory(
      remotePath,
      cancel: cancel,
      onProgress: (found) => onProgress?.call(
        TransferProgress(
          label: folderName,
          phase: TransferPhase.scanning,
          itemIndex: found,
        ),
      ),
    );
    cancel?.throwIfCancelled();
    final files = entries.where((entry) => !entry.isDirectory).toList();

    if (files.isEmpty) {
      return SavedDownload(fileName: folderName, fileCount: 0);
    }

    final knownTotal = files.every((file) => file.size != null)
        ? files.fold<int>(0, (sum, file) => sum + (file.size ?? 0))
        : null;
    var bytesBefore = 0;
    var completed = 0;

    for (final file in files) {
      cancel?.throwIfCancelled();
      final localPath =
          '${tempDir.path}/download_${DateTime.now().microsecondsSinceEpoch}_'
          '${_sanitizeSegment(file.relativePath.split('/').last)}';
      final index = completed + 1;
      var fileBytes = 0;
      try {
        await sftp.downloadFile(
          file.remotePath,
          localPath,
          cancel: cancel,
          onProgress: (received, total) {
            fileBytes = received;
            final overall = bytesBefore + received;
            final fraction = knownTotal != null
                ? _fractionOf(overall, knownTotal)
                : ((completed + (_fractionOf(received, total) ?? 0)) /
                          files.length)
                      .clamp(0.0, 1.0);
            onProgress?.call(
              TransferProgress(
                label: file.relativePath,
                itemIndex: index,
                itemCount: files.length,
                bytes: overall,
                totalBytes: knownTotal,
                fraction: fraction,
              ),
            );
            notification.report(fraction);
          },
        );

        final segments = file.relativePath.split('/');
        final subDirectories = segments
            .sublist(0, segments.length - 1)
            .map(_sanitizeSegment)
            .join('/');
        await _save(
          sourcePath: localPath,
          fileName: segments.last,
          relativePath: [
            _sanitizeSegment(folderName),
            if (subDirectories.isNotEmpty) subDirectories,
          ].join('/'),
        );
      } finally {
        await _deleteQuietly(localPath);
      }
      bytesBefore += fileBytes;
      completed++;
    }

    return SavedDownload(
      fileName: _sanitizeSegment(folderName),
      fileCount: files.length,
    );
  }

  /// Writes one finished file out, into the folder the user picked if there is
  /// one. A grant that has gone stale since it was chosen falls back to the
  /// system Downloads folder rather than failing the transfer - the setting is
  /// dropped at the same time, so the next file does not retry a dead URI.
  static Future<String?> _save({
    required String sourcePath,
    required String fileName,
    String? relativePath,
  }) async {
    if (isAndroidPlatform) {
      final folder = await DownloadLocation.instance.current();
      try {
        return await _channel.invokeMethod<String>('saveToDownloads', {
          'sourcePath': sourcePath,
          'fileName': fileName,
          'relativePath': ?relativePath,
          'treeUri': ?folder?.uri,
        });
      } on PlatformException catch (error) {
        if (folder == null || error.code != 'FOLDER_UNAVAILABLE') rethrow;
        await DownloadLocation.instance.forget();
        return _channel.invokeMethod<String>('saveToDownloads', {
          'sourcePath': sourcePath,
          'fileName': fileName,
          'relativePath': ?relativePath,
        });
      }
    } else {
      final sub = relativePath != null && relativePath.isNotEmpty
          ? '/$relativePath'
          : '';
      final Directory base;
      if (isDesktopPlatform) {
        base = await DownloadLocation.instance.desktopTarget();
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        base = Directory('${docsDir.path}/Downloads');
      }
      final targetDir = Directory('${base.path}$sub');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      final destFile = _uniqueLocalFile(targetDir, fileName);
      await File(sourcePath).copy(destFile.path);
      return destFile.path;
    }
  }

  static File _uniqueLocalFile(Directory dir, String name) {
    var candidate = File('${dir.path}/$name');
    if (!candidate.existsSync()) return candidate;

    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var counter = 1;
    while (candidate.existsSync()) {
      candidate = File('${dir.path}/$base ($counter)$ext');
      counter++;
    }
    return candidate;
  }

  static double? _fractionOf(int done, int? total) {
    if (total == null || total <= 0) return null;
    return (done / total).clamp(0.0, 1.0);
  }

  static String _joinPath(String parent, String name) =>
      parent.endsWith('/') ? '$parent$name' : '$parent/$name';

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Keeps a remote name usable as an Android Downloads path segment.
  static String _sanitizeSegment(String segment) {
    final cleaned = segment.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? '_' : cleaned;
  }
}

/// The Android notification that mirrors a transfer. One per download, torn
/// down on every exit path - a stuck progress notification outlives the app
/// and there is no way for the user to clear it.
class _DownloadNotification {
  _DownloadNotification._(this.id, this.title);

  final int id;
  final String title;
  int _lastPercent = -1;

  static Future<_DownloadNotification> start(
    String title, {
    CancelToken? cancel,
  }) async {
    DownloadService._ensureMethodCallHandler();
    final id = DownloadService._rng.nextInt(0x7FFFFFFF);
    if (cancel != null) {
      DownloadService._activeDownloads[id] = cancel;
    }
    final notification = _DownloadNotification._(id, title);
    if (isAndroidPlatform) {
      await DownloadService._channel.invokeMethod('showProgress', {
        'id': notification.id,
        'fileName': title,
        'progress': 0,
        'channelName': t.notifications.downloadProgressChannelName,
        'channelDescription':
            t.notifications.downloadProgressChannelDescription,
        'cancelLabel': t.common.cancel,
      });
      notification._lastPercent = 0;
    }
    return notification;
  }

  /// Android rate-limits notification updates, so this only posts every few
  /// percent. A null fraction means the size is unknown; the notification
  /// stays where it is rather than pretending to advance.
  void report(double? fraction) {
    if (!isAndroidPlatform) return;
    if (fraction == null) return;
    final percent = (fraction * 100).round().clamp(0, 100);
    if (percent < _lastPercent + 3 || percent >= 100) return;
    _lastPercent = percent;
    DownloadService._channel.invokeMethod('showProgress', {
      'id': id,
      'fileName': title,
      'progress': percent,
      'channelName': t.notifications.downloadProgressChannelName,
      'channelDescription': t.notifications.downloadProgressChannelDescription,
      'cancelLabel': t.common.cancel,
    });
  }

  /// [announce] is false for one entry of a selection, which posts a single
  /// notification for the whole batch instead - the local notification carries
  /// a fixed id, so one per entry would overwrite itself down to whichever
  /// file happened to finish last. The platform channel below is unaffected:
  /// each entry has always had its own native notification.
  Future<void> complete(
    String fileName, {
    int fileCount = 1,
    String? uri,
    bool announce = true,
  }) async {
    DownloadService._activeDownloads.remove(id);
    if (announce) {
      await LocalNotificationsService.instance.showTransferComplete(
        fileName: fileName,
        fileCount: fileCount,
      );
    }
    if (!isAndroidPlatform) return;
    await DownloadService._channel.invokeMethod('showComplete', {
      'id': id,
      'fileName': fileName,
      'uri': uri,
      'channelName': t.notifications.downloadCompleteChannelName,
      'channelDescription': t.notifications.downloadCompleteChannelDescription,
      'savedLabel': t.notifications.downloadSaved,
    });
  }

  /// [error] is positional and required so that a caller cannot omit it and
  /// silently report a cancellation as a failure.
  Future<void> dismiss(Object? error, {bool announce = true}) async {
    DownloadService._activeDownloads.remove(id);
    if (announce && error is! TransferCancelled) {
      await LocalNotificationsService.instance.showTransferFailed(
        fileName: title,
      );
    }
    if (!isAndroidPlatform) return;
    try {
      await DownloadService._channel.invokeMethod('cancelNotification', {
        'id': id,
      });
    } catch (_) {}
  }
}
