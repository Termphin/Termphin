import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pinenacl/ed25519.dart' as nacl;

import 'appcast_parser.dart';

/// Ed25519 public key matching `SUPublicEDKey` in `macos/Runner/Info.plist`,
/// used to verify signed Linux AppImage releases before replacing the binary.
const kTermphinUpdatePublicKeyBase64 =
    'TN6z5N9lFs3hMVH5g1pXsjz+mV+13+bsv4hMnfovQvs=';

/// Where Linux AppImage builds look for new releases. Overridden at build time
/// via `--dart-define=LINUX_APPCAST_URL=...` when testing updates.
const kLinuxAppcastUrl = String.fromEnvironment(
  'LINUX_APPCAST_URL',
  defaultValue:
      'https://github.com/Termphin/Termphin/releases/latest/download/appcast-linux.xml',
);

/// Current phase of a Linux AppImage update.
enum LinuxUpdateStage { downloading, verifying }

/// Progress snapshot emitted while downloading and verifying an update.
class LinuxUpdateProgress {
  const LinuxUpdateProgress({
    required this.stage,
    required this.received,
    this.total,
  });

  final LinuxUpdateStage stage;
  final int received;
  final int? total;

  /// Download progress in `0.0..1.0`, or `null` when the total size is unknown.
  double? get fraction {
    if (stage == LinuxUpdateStage.verifying) return 1.0;
    final t = total;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0);
  }
}

/// Token allowing the user to abort an in-flight update download.
class LinuxUpdateCancelToken {
  bool _cancelled = false;
  VoidCallback? _onCancel;

  bool get isCancelled => _cancelled;

  void attach(VoidCallback onCancel) {
    _onCancel = onCancel;
    if (_cancelled) onCancel();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// Raised when an update cannot be fetched, verified, or written safely.
class LinuxUpdateException implements Exception {
  const LinuxUpdateException(this.message);

  final String message;

  @override
  String toString() => 'LinuxUpdateException: $message';
}

/// Raised when the user cancels an update download.
class LinuxUpdateCancelledException implements Exception {
  const LinuxUpdateCancelledException();
}

/// Checks a Sparkle-signed `appcast-linux.xml`, verifies the downloaded
/// AppImage with Ed25519, atomically replaces the running `$APPIMAGE` file,
/// and relaunches the new version.
class LinuxSelfUpdater {
  LinuxSelfUpdater({
    required this.appImagePath,
    Uri? feedUri,
    String? publicKeyBase64,
    Future<({String version, String buildNumber})> Function()? readPackageInfo,
    HttpClient Function()? httpClientFactory,
    Future<void> Function(String path)? makeExecutable,
    Future<void> Function(String path)? relaunch,
  }) : feedUri = feedUri ?? Uri.parse(kLinuxAppcastUrl),
       _publicKeyBytes = Uint8List.fromList(
         base64Decode(publicKeyBase64 ?? kTermphinUpdatePublicKeyBase64),
       ),
       _readPackageInfo = readPackageInfo ?? _defaultPackageInfo,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _makeExecutable = makeExecutable ?? _defaultMakeExecutable,
       _relaunch = relaunch ?? _defaultRelaunch;

  final String appImagePath;
  final Uri feedUri;
  final Uint8List _publicKeyBytes;
  final Future<({String version, String buildNumber})> Function()
  _readPackageInfo;
  final HttpClient Function() _httpClientFactory;
  final Future<void> Function(String path) _makeExecutable;
  final Future<void> Function(String path) _relaunch;

  static const _maxRedirects = 5;

  /// Only `https://` is trusted in production; loopback `http://` stays open
  /// for local test servers.
  @visibleForTesting
  static bool isAllowedUri(Uri uri) {
    if (uri.scheme == 'https') return uri.hasAuthority;
    if (uri.scheme == 'http') {
      final host = uri.host.toLowerCase();
      return host == 'localhost' || host == '127.0.0.1' || host == '::1';
    }
    return false;
  }

  /// Fetches the feed and returns the newer release if one exists.
  Future<AppcastEntry?> checkForUpdate() async {
    final xmlBytes = await _downloadBytes(feedUri);
    final xml = utf8.decode(xmlBytes);
    final candidate = parseAppcast(xml, os: 'linux');
    if (candidate == null) return null;

    final info = await _readPackageInfo();
    if (!isNewerAppcastEntry(
      candidate,
      currentBuild: info.buildNumber,
      currentVersion: info.version,
    )) {
      return null;
    }
    return candidate;
  }

  /// Downloads [entry], verifies its byte length and Ed25519 signature, and
  /// atomically replaces [appImagePath]. Leaves the existing file untouched if
  /// any check fails or [cancelToken] cancels.
  Future<void> downloadAndInstall(
    AppcastEntry entry, {
    void Function(LinuxUpdateProgress progress)? onProgress,
    LinuxUpdateCancelToken? cancelToken,
  }) async {
    final sigBytes = _decodeSignature(entry.edSignature);
    final target = File(appImagePath);
    final parent = target.parent;
    if (!parent.existsSync()) {
      throw LinuxUpdateException(
        'Target directory does not exist: ${parent.path}',
      );
    }

    final fileName = target.uri.pathSegments.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => 'Termphin.AppImage',
    );
    final tempFile = File(
      '${parent.path}${Platform.pathSeparator}.$fileName.update.$pid',
    );

    try {
      onProgress?.call(
        LinuxUpdateProgress(
          stage: LinuxUpdateStage.downloading,
          received: 0,
          total: entry.length,
        ),
      );
      final bytes = await _downloadBytes(
        entry.downloadUrl,
        expectedTotal: entry.length,
        cancelToken: cancelToken,
        onProgress: (received, total) => onProgress?.call(
          LinuxUpdateProgress(
            stage: LinuxUpdateStage.downloading,
            received: received,
            total: total,
          ),
        ),
      );
      if (cancelToken?.isCancelled ?? false) {
        throw const LinuxUpdateCancelledException();
      }
      if (entry.length != null && bytes.length != entry.length) {
        throw LinuxUpdateException(
          'Downloaded size ${bytes.length} did not match appcast ${entry.length}',
        );
      }

      onProgress?.call(
        LinuxUpdateProgress(
          stage: LinuxUpdateStage.verifying,
          received: bytes.length,
          total: bytes.length,
        ),
      );
      _verifySignature(bytes, sigBytes);
      await tempFile.writeAsBytes(bytes, flush: true);
      await _makeExecutable(tempFile.path);
      tempFile.renameSync(target.path);
    } finally {
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Launches the replaced AppImage and exits the current process.
  Future<void> restartApp() => _relaunch(appImagePath);

  Uint8List _decodeSignature(String encoded) {
    try {
      final raw = Uint8List.fromList(base64Decode(encoded.trim()));
      if (raw.length != nacl.Signature.signatureLength) {
        throw const LinuxUpdateException('Invalid Ed25519 signature length');
      }
      return raw;
    } on FormatException {
      throw const LinuxUpdateException('Malformed Ed25519 signature');
    }
  }

  void _verifySignature(Uint8List payload, Uint8List signature) {
    try {
      final key = nacl.VerifyKey(_publicKeyBytes);
      final ok = key.verify(
        signature: nacl.Signature(signature),
        message: payload,
      );
      if (!ok) {
        throw const LinuxUpdateException(
          'Ed25519 signature verification failed',
        );
      }
    } catch (error) {
      if (error is LinuxUpdateException) rethrow;
      throw LinuxUpdateException('Ed25519 signature rejected: $error');
    }
  }

  Future<Uint8List> _downloadBytes(
    Uri initialUri, {
    int? expectedTotal,
    LinuxUpdateCancelToken? cancelToken,
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = _httpClientFactory();
    cancelToken?.attach(() => client.close(force: true));
    try {
      var current = initialUri;
      for (var hop = 0; hop <= _maxRedirects; hop++) {
        if (cancelToken?.isCancelled ?? false) {
          throw const LinuxUpdateCancelledException();
        }
        if (!isAllowedUri(current)) {
          throw LinuxUpdateException('Blocked non-HTTPS update URL: $current');
        }
        final request = await client.getUrl(current);
        request.followRedirects = false;
        final response = await request.close();

        if (response.isRedirect ||
            (response.statusCode >= 300 && response.statusCode < 400)) {
          await response.drain<void>();
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || location.isEmpty) {
            throw const LinuxUpdateException('Redirect missing Location header');
          }
          current = current.resolve(location);
          continue;
        }

        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw LinuxUpdateException(
            'HTTP ${response.statusCode} fetching $current',
          );
        }

        final total =
            response.contentLength >= 0 ? response.contentLength : expectedTotal;
        final builder = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk in response) {
          if (cancelToken?.isCancelled ?? false) {
            throw const LinuxUpdateCancelledException();
          }
          builder.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        return builder.takeBytes();
      }
      throw LinuxUpdateException('Too many redirects fetching $initialUri');
    } catch (error) {
      if (cancelToken?.isCancelled ?? false) {
        throw const LinuxUpdateCancelledException();
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<({String version, String buildNumber})>
  _defaultPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    return (version: info.version, buildNumber: info.buildNumber);
  }

  static Future<void> _defaultMakeExecutable(String path) async {
    final result = await Process.run('chmod', ['+x', path]);
    if (result.exitCode != 0) {
      throw LinuxUpdateException('chmod +x failed: ${result.stderr}');
    }
  }

  static Future<void> _defaultRelaunch(String path) async {
    await Process.start(path, const [], mode: ProcessStartMode.detached);
    exit(0);
  }
}
