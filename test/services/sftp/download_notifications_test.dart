import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/sftp/cancel_token.dart';
import 'package:termphin/services/sftp/download_location.dart';
import 'package:termphin/services/sftp/download_service.dart';
import 'package:termphin/services/sftp/sftp_service.dart';

class _UnusedSshClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSftpService extends SftpService {
  _FakeSftpService({this.error}) : super(_UnusedSshClient());

  final Object? error;

  @override
  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    void Function(int received, int? total)? onProgress,
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    await File(localPath).writeAsString('fake');
    onProgress?.call(4, 4);
    if (error != null) throw error!;
  }
}

/// What a finished transfer announces on iOS, where there is no native side to
/// post it. Android is covered by `download_service_test.dart`, which asserts
/// the channel calls; this file is only about the local notification.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const downloadsChannel = MethodChannel('dev.termphin.termphin/downloads');
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  late Directory tempDirectory;
  late List<Map<Object?, Object?>> shown;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    DownloadLocation.instance.invalidateCache();
    tempDirectory = await Directory.systemTemp.createTemp('termphin-notif-');
    shown = [];

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, (call) async {
      return tempDirectory.path;
    });
    messenger.setMockMethodCallHandler(downloadsChannel, (call) async => null);
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'checkPermissions':
          return <String, dynamic>{'isEnabled': true};
        case 'show':
          shown.add(call.arguments as Map<Object?, Object?>);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    DownloadLocation.instance.invalidateCache();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(downloadsChannel, null);
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    await tempDirectory.delete(recursive: true);
  });

  List<String> bodies() => [for (final call in shown) call['body'] as String];

  test('a single file announces itself by name', () async {
    await DownloadService.downloadSftpFile(
      sftp: _FakeSftpService(),
      remotePath: '/remote/a.txt',
      fileName: 'a.txt',
    );

    expect(bodies(), [t.notifications.transferDoneOne(name: 'a.txt')]);
  });

  test('a selection of several files announces once, with the count', () async {
    await DownloadService.downloadSftpSelection(
      sftp: _FakeSftpService(),
      parentPath: '/remote',
      entries: const [
        SftpEntryRef(name: 'a.txt', isDirectory: false, size: 4),
        SftpEntryRef(name: 'b.txt', isDirectory: false, size: 4),
        SftpEntryRef(name: 'c.txt', isDirectory: false, size: 4),
      ],
      multiFileLabel: 'Downloads',
    );

    expect(bodies(), [
      t.notifications.transferDoneMany(count: 3, folder: 'Downloads'),
    ]);
  });

  test('a cancelled transfer announces nothing', () async {
    await expectLater(
      DownloadService.downloadSftpFile(
        sftp: _FakeSftpService(),
        remotePath: '/remote/a.txt',
        fileName: 'a.txt',
        cancel: CancelToken()..cancel(),
      ),
      throwsA(isA<TransferCancelled>()),
    );

    expect(shown, isEmpty);
  });

  test('a failed transfer announces the failure once', () async {
    await expectLater(
      DownloadService.downloadSftpFile(
        sftp: _FakeSftpService(error: StateError('boom')),
        remotePath: '/remote/a.txt',
        fileName: 'a.txt',
      ),
      throwsA(isA<StateError>()),
    );

    expect(bodies(), [t.notifications.transferFailedBody(name: 'a.txt')]);
  });

  test('a failed entry in a selection announces the failure once', () async {
    await expectLater(
      DownloadService.downloadSftpSelection(
        sftp: _FakeSftpService(error: StateError('boom')),
        parentPath: '/remote',
        entries: const [
          SftpEntryRef(name: 'a.txt', isDirectory: false, size: 4),
          SftpEntryRef(name: 'b.txt', isDirectory: false, size: 4),
        ],
        multiFileLabel: 'Downloads',
      ),
      throwsA(isA<StateError>()),
    );

    expect(bodies(), [t.notifications.transferFailedBody(name: 'Downloads')]);
  });
}
