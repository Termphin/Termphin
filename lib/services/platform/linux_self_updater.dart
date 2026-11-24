import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pinenacl/ed25519.dart' as nacl;

import 'appcast_fetcher.dart';
import 'appcast_parser.dart';

export 'appcast_fetcher.dart'
    show
        LinuxUpdateCancelToken,
        LinuxUpdateCancelledException,
        LinuxUpdateException;

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
       _readPackageInfo = readPackageInfo,
       _httpClientFactory = httpClientFactory,
       _makeExecutable = makeExecutable ?? _defaultMakeExecutable,
       _relaunch = relaunch ?? _defaultRelaunch;

  final String appImagePath;
  final Uri feedUri;
  final Uint8List _publicKeyBytes;
  final Future<({String version, String buildNumber})> Function()?
  _readPackageInfo;
  final HttpClient Function()? _httpClientFactory;
  final Future<void> Function(String path) _makeExecutable;
  final Future<void> Function(String path) _relaunch;

  /// Only `https://` is trusted in production; loopback `http://` stays open
  /// for local test servers.
  @visibleForTesting
  static bool isAllowedUri(Uri uri) => isAllowedUpdateUri(uri);

  /// Fetches the feed and returns the newer release if one exists.
  Future<AppcastEntry?> checkForUpdate() => fetchNewerAppcastEntry(
    feedUri: feedUri,
    os: 'linux',
    readPackageInfo: _readPackageInfo,
    httpClientFactory: _httpClientFactory,
  );

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
      final bytes = await downloadAppcastBytes(
        entry.downloadUrl,
        expectedTotal: entry.length,
        cancelToken: cancelToken,
        httpClientFactory: _httpClientFactory,
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
