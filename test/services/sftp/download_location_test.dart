import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/sftp/download_location.dart';

/// A Linux session without XDG user directories - no `user-dirs.dirs`, as
/// on a server or a bare window manager - reports neither a Downloads nor a
/// Documents folder, and a download there failed with
/// `MissingPlatformDirectoryException` instead of landing somewhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DownloadLocation.instance.invalidateCache();
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => null);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
  });

  test('falls back to Downloads in the home folder', () async {
    final target = await DownloadLocation.instance.desktopTarget();
    expect(target.path, '${Platform.environment['HOME']}/Downloads');
  });

  group('desktopFolderPath', () {
    test('turns the file URI a desktop picker answers with into a path', () {
      expect(
        desktopFolderPath(Uri.file('/home/me/My Downloads', windows: false)),
        '/home/me/My Downloads',
      );
    });

    test('is null when nothing was picked or the answer is no file URI', () {
      expect(desktopFolderPath(null), isNull);
      expect(
        desktopFolderPath(Uri.parse('content://com.android/tree/primary%3A')),
        isNull,
      );
    });
  });
}
