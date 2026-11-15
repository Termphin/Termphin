import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The account's profile picture, kept on the device: fetched once from
/// Google or GitHub and read from disk after that, so the avatar is there at
/// once on every launch and offline. A changed picture has a new address,
/// and so a new file; signing out deletes it.
class AccountPhotos {
  AccountPhotos({
    @visibleForTesting Future<Uint8List> Function(Uri url)? fetch,
    @visibleForTesting Future<Directory> Function()? directory,
  }) : _fetch = fetch ?? _download,
       _directory = directory ?? _defaultDirectory;

  static final instance = AccountPhotos();

  final Future<Uint8List> Function(Uri url) _fetch;
  final Future<Directory> Function() _directory;
  final _pending = <String, Future<File?>>{};

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/account');

  /// The picture at [url] as a file on the device, fetched the first time
  /// it is asked for. Null when it cannot be had; the avatar then keeps its
  /// letter.
  Future<File?> fileFor(String url) =>
      _pending[url] ??= _load(url).whenComplete(() {
        _pending.remove(url);
      });

  Future<File?> _load(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    try {
      final directory = await _directory();
      final file = File('${directory.path}/${sha256.convert(url.codeUnits)}');
      if (await file.exists()) return file;
      final bytes = await _fetch(uri);
      if (bytes.isEmpty) return null;
      await directory.create(recursive: true);
      await for (final entry in directory.list()) {
        if (entry is File) await entry.delete();
      }
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the kept picture, as signing out does.
  Future<void> clear() async {
    try {
      final directory = await _directory();
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  static Future<Uint8List> _download(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return Uint8List(0);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > 2 * 1024 * 1024) return Uint8List(0);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }
}
