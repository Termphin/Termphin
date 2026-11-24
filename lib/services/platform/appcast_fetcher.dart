import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:package_info_plus/package_info_plus.dart';

import 'appcast_parser.dart';

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

/// Token allowing the user to abort an in-flight update download.
class LinuxUpdateCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void attach(void Function() onCancel) {
    _onCancel = onCancel;
    if (_cancelled) onCancel();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// Only `https://` is trusted in production; loopback `http://` stays open
/// for local test servers.
bool isAllowedUpdateUri(Uri uri) {
  if (uri.scheme == 'https') return uri.hasAuthority;
  if (uri.scheme == 'http') {
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }
  return false;
}

/// Downloads bytes from [initialUri], validating HTTPS on every redirect hop.
Future<Uint8List> downloadAppcastBytes(
  Uri initialUri, {
  int? expectedTotal,
  LinuxUpdateCancelToken? cancelToken,
  HttpClient Function()? httpClientFactory,
  void Function(int received, int? total)? onProgress,
}) async {
  const maxRedirects = 5;
  final client = (httpClientFactory ?? HttpClient.new)();
  cancelToken?.attach(() => client.close(force: true));
  try {
    var current = initialUri;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      if (cancelToken?.isCancelled ?? false) {
        throw const LinuxUpdateCancelledException();
      }
      if (!isAllowedUpdateUri(current)) {
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

/// Fetches [feedUri], parses the entry for [os], and returns it only when it
/// is newer than the currently running build.
Future<AppcastEntry?> fetchNewerAppcastEntry({
  required Uri feedUri,
  required String os,
  Future<({String version, String buildNumber})> Function()? readPackageInfo,
  HttpClient Function()? httpClientFactory,
}) async {
  final xmlBytes = await downloadAppcastBytes(
    feedUri,
    httpClientFactory: httpClientFactory,
  );
  final xml = utf8.decode(xmlBytes);
  final candidate = parseAppcast(xml, os: os);
  if (candidate == null) return null;

  final info = await (readPackageInfo ?? defaultUpdatePackageInfo)();
  if (!isNewerAppcastEntry(
    candidate,
    currentBuild: info.buildNumber,
    currentVersion: info.version,
  )) {
    return null;
  }
  return candidate;
}

/// Reads the running version and build number from [PackageInfo].
Future<({String version, String buildNumber})> defaultUpdatePackageInfo() async {
  final info = await PackageInfo.fromPlatform();
  return (version: info.version, buildNumber: info.buildNumber);
}
