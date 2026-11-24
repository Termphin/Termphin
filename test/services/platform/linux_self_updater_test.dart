import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:termphin/services/platform/appcast_parser.dart';
import 'package:termphin/services/platform/linux_self_updater.dart';

String _buildAppcast({
  required String version,
  required String build,
  required String url,
  required String signature,
  required int length,
  String os = 'linux',
}) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Termphin</title>
    <item>
      <title>Termphin $version</title>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <enclosure url="$url" length="$length" type="application/octet-stream" sparkle:os="$os" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
''';

void main() {
  group('appcast_parser', () {
    test('picks newest matching OS entry and decodes XML entities', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:version>950</sparkle:version>
      <sparkle:shortVersionString>2.0.0</sparkle:shortVersionString>
      <enclosure url="https://example.com/Termphin.dmg" length="10" sparkle:os="macos" sparkle:edSignature="macsig=="/>
    </item>
    <item>
      <sparkle:version>900</sparkle:version>
      <sparkle:shortVersionString>1.16.1</sparkle:shortVersionString>
      <enclosure url="https://example.com/a.AppImage?x=1&amp;y=2" length="20" sparkle:os="linux" sparkle:edSignature="sig1=="/>
    </item>
    <item>
      <sparkle:version>902</sparkle:version>
      <sparkle:shortVersionString>1.17.0</sparkle:shortVersionString>
      <enclosure url="https://example.com/b.AppImage?x=1&amp;y=2" length="30" sparkle:os="linux" sparkle:edSignature="sig2=="/>
    </item>
  </channel>
</rss>
''';

      final entry = parseAppcast(xml, os: 'linux');
      expect(entry, isNotNull);
      expect(entry!.buildNumber, '902');
      expect(entry.version, '1.17.0');
      expect(
        entry.downloadUrl.toString(),
        'https://example.com/b.AppImage?x=1&y=2',
      );
      expect(entry.length, 30);
      expect(entry.edSignature, 'sig2==');
    });

    test('compares build numbers numerically and falls back to semver', () {
      final entry = AppcastEntry(
        version: '1.17.0',
        buildNumber: '100',
        downloadUrl: Uri.parse('https://example.com/a.AppImage'),
        edSignature: 'sig==',
      );

      expect(
        isNewerAppcastEntry(
          entry,
          currentBuild: '99',
          currentVersion: '1.16.1',
        ),
        isTrue,
      );
      expect(
        isNewerAppcastEntry(
          entry,
          currentBuild: '100',
          currentVersion: '1.16.1',
        ),
        isFalse,
      );
    });
  });

  group('LinuxSelfUpdater', () {
    test('allows only HTTPS or loopback HTTP URIs', () {
      expect(
        LinuxSelfUpdater.isAllowedUri(
          Uri.parse('https://github.com/Termphin/Termphin/releases/latest'),
        ),
        isTrue,
      );
      expect(
        LinuxSelfUpdater.isAllowedUri(Uri.parse('http://127.0.0.1:8080/feed')),
        isTrue,
      );
      expect(
        LinuxSelfUpdater.isAllowedUri(Uri.parse('http://localhost/feed')),
        isTrue,
      );
      expect(
        LinuxSelfUpdater.isAllowedUri(Uri.parse('http://example.com/feed')),
        isFalse,
      );
      expect(
        LinuxSelfUpdater.isAllowedUri(Uri.parse('file:///tmp/app.AppImage')),
        isFalse,
      );
    });

    test('verifies Ed25519 signature and atomically replaces AppImage', () async {
      final dir = Directory.systemTemp.createTempSync('termphin-updater-');
      addTearDown(() => dir.deleteSync(recursive: true));

      final target = File('${dir.path}/Termphin.AppImage');
      await target.writeAsBytes(utf8.encode('old-appimage-binary'));

      final signingKey = nacl.SigningKey.generate();
      final pubBase64 = base64Encode(signingKey.verifyKey.asTypedList);
      final newPayload = utf8.encode('new-appimage-binary-v2');
      final sigBytes = signingKey.sign(Uint8List.fromList(newPayload)).signature;
      final sigBase64 = base64Encode(sigBytes.asTypedList);

      late HttpServer server;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        if (req.uri.path == '/appcast-linux.xml') {
          req.response
            ..statusCode = HttpStatus.ok
            ..write(
              _buildAppcast(
                version: '1.17.0',
                build: '901',
                url: '$baseUrl/Termphin.AppImage',
                signature: sigBase64,
                length: newPayload.length,
              ),
            );
        } else if (req.uri.path == '/Termphin.AppImage') {
          req.response
            ..statusCode = HttpStatus.ok
            ..add(newPayload);
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });

      var madeExecutablePath = '';
      final updater = LinuxSelfUpdater(
        appImagePath: target.path,
        feedUri: Uri.parse('$baseUrl/appcast-linux.xml'),
        publicKeyBase64: pubBase64,
        readPackageInfo: () async => (version: '1.16.1', buildNumber: '900'),
        makeExecutable: (path) async {
          madeExecutablePath = path;
          final res = await Process.run('chmod', ['+x', path]);
          expect(res.exitCode, 0);
        },
      );

      final update = await updater.checkForUpdate();
      expect(update, isNotNull);
      expect(update!.buildNumber, '901');

      final progressEvents = <LinuxUpdateProgress>[];
      await updater.downloadAndInstall(
        update,
        onProgress: progressEvents.add,
      );

      expect(progressEvents.first.stage, LinuxUpdateStage.downloading);
      expect(progressEvents.last.stage, LinuxUpdateStage.verifying);
      expect(progressEvents.last.fraction, 1.0);
      expect(madeExecutablePath, contains('.Termphin.AppImage.update.'));
      expect(await target.readAsBytes(), newPayload);
      expect(
        dir.listSync().where((e) => e.path.contains('.update.')),
        isEmpty,
      );
      final stat = await target.stat();
      expect(stat.mode & 0x49, isNonZero);
    });

    test('rejects tampered payload and keeps original AppImage untouched', () async {
      final dir = Directory.systemTemp.createTempSync('termphin-updater-bad-');
      addTearDown(() => dir.deleteSync(recursive: true));

      final originalBytes = utf8.encode('good-existing-appimage');
      final target = File('${dir.path}/Termphin.AppImage');
      await target.writeAsBytes(originalBytes);

      final signingKey = nacl.SigningKey.generate();
      final pubBase64 = base64Encode(signingKey.verifyKey.asTypedList);
      final expectedPayload = utf8.encode('authentic-payload');
      final tamperedPayload = utf8.encode('tampered!-payload');
      final sigBase64 = base64Encode(
        signingKey.sign(Uint8List.fromList(expectedPayload)).signature.asTypedList,
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..add(tamperedPayload);
        await req.response.close();
      });

      final updater = LinuxSelfUpdater(
        appImagePath: target.path,
        feedUri: Uri.parse('$baseUrl/appcast-linux.xml'),
        publicKeyBase64: pubBase64,
        readPackageInfo: () async => (version: '1.16.1', buildNumber: '900'),
      );

      final entry = AppcastEntry(
        version: '1.17.0',
        buildNumber: '901',
        downloadUrl: Uri.parse('$baseUrl/Termphin.AppImage'),
        edSignature: sigBase64,
        length: expectedPayload.length,
      );

      await expectLater(
        updater.downloadAndInstall(entry),
        throwsA(isA<LinuxUpdateException>()),
      );
      expect(await target.readAsBytes(), originalBytes);
      expect(
        dir.listSync().where((e) => e.path.contains('.update.')),
        isEmpty,
      );
    });

    test('cancelling mid-download cleans up temp file and keeps existing AppImage', () async {
      final dir = Directory.systemTemp.createTempSync('termphin-updater-cancel-');
      addTearDown(() => dir.deleteSync(recursive: true));

      final originalBytes = utf8.encode('good-existing-appimage');
      final target = File('${dir.path}/Termphin.AppImage');
      await target.writeAsBytes(originalBytes);

      final signingKey = nacl.SigningKey.generate();
      final pubBase64 = base64Encode(signingKey.verifyKey.asTypedList);
      final sigBase64 = base64Encode(
        signingKey.sign(Uint8List.fromList([1, 2, 3])).signature.asTypedList,
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final firstChunkSent = Completer<void>();
      server.listen((req) async {
        req.response.statusCode = HttpStatus.ok;
        req.response.contentLength = 1024;
        req.response.add(List<int>.filled(64, 1));
        await req.response.flush();
        if (!firstChunkSent.isCompleted) firstChunkSent.complete();
      });

      final cancelToken = LinuxUpdateCancelToken();
      final updater = LinuxSelfUpdater(
        appImagePath: target.path,
        feedUri: Uri.parse('http://127.0.0.1:${server.port}/appcast-linux.xml'),
        publicKeyBase64: pubBase64,
        readPackageInfo: () async => (version: '1.16.1', buildNumber: '900'),
      );

      final entry = AppcastEntry(
        version: '1.17.0',
        buildNumber: '901',
        downloadUrl: Uri.parse('http://127.0.0.1:${server.port}/Termphin.AppImage'),
        edSignature: sigBase64,
        length: 1024,
      );

      final future = updater.downloadAndInstall(
        entry,
        cancelToken: cancelToken,
      );
      await firstChunkSent.future;
      cancelToken.cancel();

      await expectLater(future, throwsA(isA<LinuxUpdateCancelledException>()));
      expect(await target.readAsBytes(), originalBytes);
      expect(
        dir.listSync().where((e) => e.path.contains('.update.')),
        isEmpty,
      );
    });
  });
}
