import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/sftp/cancel_token.dart';
import 'package:termphin/services/sftp/download_location.dart';
import 'package:termphin/services/sftp/download_service.dart';
import 'package:termphin/services/sftp/sftp_service.dart';

class _UnusedSshClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSftpService extends SftpService {
  _FakeSftpService({
    this.progress = const [],
    this.error,
    this.walkEntries = const [],
  }) : super(_UnusedSshClient());

  final List<double> progress;
  final Object? error;
  final List<SftpWalkEntry> walkEntries;

  /// Size the fake transfers report, so a fraction can be turned back into
  /// the byte counts the real service hands out.
  static const fileSize = 100;

  String? downloadedRemotePath;
  String? downloadedLocalPath;
  final List<String> downloadedRemotePaths = [];

  @override
  Future<List<SftpWalkEntry>> walkDirectory(
    String path, {
    void Function(int found)? onProgress,
    CancelToken? cancel,
  }) async {
    onProgress?.call(0);
    return walkEntries;
  }

  @override
  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    void Function(int received, int? total)? onProgress,
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    downloadedRemotePath = remotePath;
    downloadedRemotePaths.add(remotePath);
    downloadedLocalPath = localPath;
    await File(localPath).writeAsString('fake');
    for (final value in progress) {
      onProgress?.call((value * fileSize).round(), fileSize);
    }
    if (error != null) throw error!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const downloadsChannel = MethodChannel('dev.termphin.termphin/downloads');
  late Directory tempDirectory;
  late List<MethodCall> calls;
  String? failingMethod;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DownloadLocation.instance.invalidateCache();
    tempDirectory = await Directory.systemTemp.createTemp('termphin-download-');
    calls = [];
    failingMethod = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
          expect(call.method, 'getTemporaryDirectory');
          return tempDirectory.path;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(downloadsChannel, (call) async {
          calls.add(call);
          if (call.method == failingMethod) {
            throw PlatformException(code: 'native_error');
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(downloadsChannel, null);
    await tempDirectory.delete(recursive: true);
  });

  test(
    'downloads to a temporary file and publishes throttled progress',
    () async {
      final sftp = _FakeSftpService(progress: [0.01, 0.02, 0.04, 0.98, 1]);
      final progress = <double?>[];

      await DownloadService.downloadSftpFile(
        sftp: sftp,
        remotePath: '/remote/report.txt',
        fileName: 'report.txt',
        onProgress: (update) => progress.add(update.fraction),
      );

      expect(sftp.downloadedRemotePath, '/remote/report.txt');
      expect(
        sftp.downloadedLocalPath,
        startsWith('${tempDirectory.path}/download_'),
      );
      expect(sftp.downloadedLocalPath, endsWith('_report.txt'));
      expect(progress, [0.01, 0.02, 0.04, 0.98, 1]);
      expect(calls.map((call) => call.method), [
        'showProgress',
        'showProgress',
        'showProgress',
        'saveToDownloads',
        'showComplete',
      ]);
      expect(
        calls
            .where((call) => call.method == 'showProgress')
            .map(
              (call) => (call.arguments as Map<Object?, Object?>)['progress'],
            ),
        [0, 4, 98],
      );
      expect(calls[3].arguments, {
        'sourcePath': sftp.downloadedLocalPath,
        'fileName': 'report.txt',
      });
      expect(await File(sftp.downloadedLocalPath!).exists(), isFalse);
    },
  );

  test('cancels the notification when the SFTP download fails', () async {
    final error = StateError('connection lost');
    final sftp = _FakeSftpService(error: error);

    await expectLater(
      DownloadService.downloadSftpFile(
        sftp: sftp,
        remotePath: '/remote/report.txt',
        fileName: 'report.txt',
      ),
      throwsA(same(error)),
    );

    expect(calls.map((call) => call.method), [
      'showProgress',
      'cancelNotification',
    ]);
    expect(calls[0].arguments, containsPair('id', isA<int>()));
    expect(calls[1].arguments, {
      'id': (calls[0].arguments as Map<Object?, Object?>)['id'],
    });
  });

  test('cancels the notification when saving to Downloads fails', () async {
    failingMethod = 'saveToDownloads';

    await expectLater(
      DownloadService.downloadSftpFile(
        sftp: _FakeSftpService(),
        remotePath: '/remote/report.txt',
        fileName: 'report.txt',
      ),
      throwsA(isA<PlatformException>()),
    );

    expect(calls.map((call) => call.method), [
      'showProgress',
      'saveToDownloads',
      'cancelNotification',
    ]);
  });

  test('copies a directory tree into Downloads keeping its shape', () async {
    final sftp = _FakeSftpService(
      walkEntries: const [
        SftpWalkEntry(
          remotePath: '/remote/site/index.html',
          relativePath: 'index.html',
          isDirectory: false,
          size: 4,
        ),
        SftpWalkEntry(
          remotePath: '/remote/site/css',
          relativePath: 'css',
          isDirectory: true,
        ),
        SftpWalkEntry(
          remotePath: '/remote/site/css/app.css',
          relativePath: 'css/app.css',
          isDirectory: false,
          size: 4,
        ),
      ],
    );

    await DownloadService.downloadSftpDirectory(
      sftp: sftp,
      remotePath: '/remote/site',
      folderName: 'site',
    );

    expect(sftp.downloadedRemotePaths, [
      '/remote/site/index.html',
      '/remote/site/css/app.css',
    ]);
    final saves = calls.where((c) => c.method == 'saveToDownloads').toList();
    expect(saves, hasLength(2));
    expect(saves.first.arguments['fileName'], 'index.html');
    expect(saves.first.arguments['relativePath'], 'site');
    expect(saves.last.arguments['fileName'], 'app.css');
    expect(saves.last.arguments['relativePath'], 'site/css');
    expect(tempDirectory.listSync(), isEmpty);
  });

  test('reports directory download progress per file', () async {
    final sftp = _FakeSftpService(
      progress: const [0.5, 1.0],
      walkEntries: const [
        SftpWalkEntry(
          remotePath: '/remote/site/a.txt',
          relativePath: 'a.txt',
          isDirectory: false,
        ),
        SftpWalkEntry(
          remotePath: '/remote/site/b.txt',
          relativePath: 'b.txt',
          isDirectory: false,
        ),
      ],
    );
    final seen = <(String, int, int, double?)>[];

    await DownloadService.downloadSftpDirectory(
      sftp: sftp,
      remotePath: '/remote/site',
      folderName: 'site',
      onProgress: (update) {
        if (update.phase != TransferPhase.transferring) return;
        seen.add((
          update.label,
          update.itemIndex,
          update.itemCount,
          update.fraction,
        ));
      },
    );

    expect(seen.first, ('a.txt', 1, 2, 0.25));
    expect(seen.last, ('b.txt', 2, 2, 1.0));
  });

  test(
    'reports byte-accurate progress when the tree announces sizes',
    () async {
      final sftp = _FakeSftpService(
        progress: const [0.5, 1.0],
        walkEntries: const [
          SftpWalkEntry(
            remotePath: '/remote/site/a.txt',
            relativePath: 'a.txt',
            isDirectory: false,
            size: _FakeSftpService.fileSize,
          ),
          SftpWalkEntry(
            remotePath: '/remote/site/b.txt',
            relativePath: 'b.txt',
            isDirectory: false,
            size: _FakeSftpService.fileSize,
          ),
        ],
      );
      final seen = <TransferProgress>[];

      await DownloadService.downloadSftpDirectory(
        sftp: sftp,
        remotePath: '/remote/site',
        folderName: 'site',
        onProgress: (update) {
          if (update.phase == TransferPhase.transferring) seen.add(update);
        },
      );

      expect(seen.first.fraction, 0.25);
      expect(seen.first.totalBytes, 200);
      expect(seen.last.bytes, 200);
      expect(seen.last.fraction, 1.0);
    },
  );

  test('stops a directory download when cancelled', () async {
    final sftp = _FakeSftpService(
      walkEntries: const [
        SftpWalkEntry(
          remotePath: '/remote/site/a.txt',
          relativePath: 'a.txt',
          isDirectory: false,
        ),
      ],
    );

    await expectLater(
      DownloadService.downloadSftpDirectory(
        sftp: sftp,
        remotePath: '/remote/site',
        folderName: 'site',
        cancel: CancelToken()..cancel(),
      ),
      throwsA(isA<TransferCancelled>()),
    );
    expect(sftp.downloadedRemotePaths, isEmpty);
    expect(calls.map((c) => c.method), contains('cancelNotification'));
  });

  test('stops a selection between entries when cancelled', () async {
    final sftp = _FakeSftpService(progress: const [0.5]);
    final cancel = CancelToken();

    await expectLater(
      DownloadService.downloadSftpSelection(
        sftp: sftp,
        parentPath: '/remote',
        entries: const [
          SftpEntryRef(name: 'a.txt', isDirectory: false),
          SftpEntryRef(name: 'b.txt', isDirectory: false),
        ],
        multiFileLabel: 'Downloads',
        onProgress: (_) => cancel.cancel(),
        cancel: cancel,
      ),
      throwsA(isA<TransferCancelled>()),
    );
    expect(sftp.downloadedRemotePaths, ['/remote/a.txt']);
  });

  test('downloads a selection one entry at a time', () async {
    final sftp = _FakeSftpService();

    final saved = await DownloadService.downloadSftpSelection(
      sftp: sftp,
      parentPath: '/remote',
      entries: const [
        SftpEntryRef(name: 'a.txt', isDirectory: false),
        SftpEntryRef(name: 'b.txt', isDirectory: false),
      ],
      multiFileLabel: 'Downloads',
    );

    expect(sftp.downloadedRemotePaths, ['/remote/a.txt', '/remote/b.txt']);
    expect(saved?.fileName, 'Downloads');
    expect(saved?.fileCount, 2);

    final progressCalls = calls
        .where((c) => c.method == 'showProgress')
        .map((c) => c.arguments as Map<Object?, Object?>)
        .toList();
    final ids = progressCalls.map((a) => a['id']).toSet();
    expect(ids, hasLength(1));
    expect(progressCalls.map((a) => a['fileName']), containsAll(['a.txt', 'b.txt']));
    expect(
      progressCalls.map((a) => a['subtitle']),
      containsAll(['Downloading (1/2)…', 'Downloading (2/2) · 50%']),
    );
    expect(
      calls.where((c) => c.method == 'showComplete'),
      hasLength(1),
    );
  });

  test('saves into the folder the user picked', () async {
    SharedPreferences.setMockInitialValues({
      'download_folder_uri': 'content://tree/primary%3ASSH',
      'download_folder_label': 'SSH',
    });
    DownloadLocation.instance.invalidateCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(downloadsChannel, (call) async {
          calls.add(call);
          return call.method == 'hasDownloadFolderAccess' ? true : null;
        });

    await DownloadService.downloadSftpFile(
      sftp: _FakeSftpService(),
      remotePath: '/remote/report.txt',
      fileName: 'report.txt',
    );

    final save = calls.lastWhere((call) => call.method == 'saveToDownloads');
    expect(save.arguments['treeUri'], 'content://tree/primary%3ASSH');
  });

  test('falls back to Downloads when the picked folder is gone', () async {
    SharedPreferences.setMockInitialValues({
      'download_folder_uri': 'content://tree/primary%3AGone',
      'download_folder_label': 'Gone',
    });
    DownloadLocation.instance.invalidateCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(downloadsChannel, (call) async {
          calls.add(call);
          if (call.method == 'hasDownloadFolderAccess') return true;
          if (call.method == 'saveToDownloads' &&
              call.arguments['treeUri'] != null) {
            throw PlatformException(code: 'FOLDER_UNAVAILABLE');
          }
          return null;
        });

    await DownloadService.downloadSftpFile(
      sftp: _FakeSftpService(),
      remotePath: '/remote/report.txt',
      fileName: 'report.txt',
    );

    final saves = calls.where((c) => c.method == 'saveToDownloads').toList();
    expect(saves, hasLength(2));
    expect(saves.last.arguments['treeUri'], isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('download_folder_uri'), isNull);
  });

  test('hands back the content uri so the file can be opened', () async {
    final sftp = _FakeSftpService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(downloadsChannel, (call) async {
          calls.add(call);
          return call.method == 'saveToDownloads'
              ? 'content://downloads/1'
              : null;
        });

    final saved = await DownloadService.downloadSftpFile(
      sftp: sftp,
      remotePath: '/remote/file.txt',
      fileName: 'file.txt',
    );

    expect(saved.uri, 'content://downloads/1');

    await DownloadService.openSavedDownload(saved);
    final open = calls.lastWhere((c) => c.method == 'openDownload');
    expect(open.arguments['uri'], 'content://downloads/1');
    expect(open.arguments['fileName'], 'file.txt');
  });

  test('TransferNotification.runUpload reports upload Live Update progress and completion', () async {
    final cancel = CancelToken();
    await TransferNotification.runUpload(
      label: 'bundle.tar.gz',
      completeTarget: 'bundle.tar.gz',
      fileCount: 1,
      cancel: cancel,
      body: (report) async {
        report(0.25);
        report(0.60);
      },
    );

    expect(calls.map((c) => c.method), [
      'showProgress',
      'showProgress',
      'showProgress',
      'showComplete',
    ]);
    final progressCalls = calls
        .where((c) => c.method == 'showProgress')
        .map((c) => c.arguments as Map<Object?, Object?>)
        .toList();
    expect(progressCalls.map((a) => a['shortText']), ['↑ …', '↑ 25%', '↑ 60%']);
    expect(progressCalls.last['subtitle'], 'Uploading · 60%');

    final completeArgs =
        calls.lastWhere((c) => c.method == 'showComplete').arguments
            as Map<Object?, Object?>;
    expect(completeArgs['fileName'], 'bundle.tar.gz');
    expect(completeArgs['savedLabel'], 'Uploaded');
  });

  test('TransferNotification.runUpload dismisses silently when showAndroidComplete is false', () async {
    await TransferNotification.runUpload(
      label: 'fast.png',
      completeTarget: 'fast.png',
      fileCount: 1,
      cancel: CancelToken(),
      showAndroidComplete: false,
      body: (report) async => report(0.5),
    );

    expect(calls.map((c) => c.method), [
      'showProgress',
      'showProgress',
      'cancelNotification',
    ]);
  });

  test('TransferNotification.runUpload cancels via notification action and cleans up', () async {
    final cancel = CancelToken();
    await expectLater(
      TransferNotification.runUpload(
        label: 'bundle.tar.gz',
        completeTarget: 'bundle.tar.gz',
        fileCount: 1,
        cancel: cancel,
        body: (_) async {
          final id =
              (calls.firstWhere((c) => c.method == 'showProgress').arguments
                      as Map<Object?, Object?>)['id']
                  as int;
          await TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .handlePlatformMessage(
                downloadsChannel.name,
                const StandardMethodCodec().encodeMethodCall(
                  MethodCall('downloadCancelRequested', {'id': id}),
                ),
                (_) {},
              );
          cancel.throwIfCancelled();
        },
      ),
      throwsA(isA<TransferCancelled>()),
    );

    expect(calls.map((c) => c.method), ['showProgress', 'cancelNotification']);
  });

  test('iOS Live Activities channel receives upload progress, complete, and cancel', () async {
    const liveActivityChannel = MethodChannel(
      'dev.termphin.termphin/live_activities',
    );
    const backgroundChannel = MethodChannel(
      'dev.termphin.termphin/background_task',
    );
    const notificationsChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    final iosCalls = <MethodCall>[];
    final bgCalls = <MethodCall>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(liveActivityChannel, (call) async {
      iosCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(backgroundChannel, (call) async {
      bgCalls.add(call);
      if (call.method == 'begin') return 77;
      return null;
    });
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'checkPermissions') {
        return <String, dynamic>{'isEnabled': true};
      }
      return null;
    });

    try {
      await TransferNotification.runUpload(
        label: 'first.bin',
        completeTarget: 'uploads',
        fileCount: 2,
        cancel: CancelToken(),
        body: (report) async {
          report(0.50, label: 'first.bin', itemIndex: 1, itemCount: 2);
          report(0.51, label: 'second.bin', itemIndex: 2, itemCount: 2);
        },
      );
      expect(bgCalls.map((c) => c.method), ['begin', 'end']);
      expect(bgCalls.first.arguments, {'name': 'upload'});
      expect(bgCalls.last.arguments, {'token': 77});

      expect(iosCalls.map((c) => c.method), [
        'showProgress',
        'showProgress',
        'showProgress',
        'showComplete',
      ]);
      final progressArgs = iosCalls
          .where((c) => c.method == 'showProgress')
          .map((c) => c.arguments as Map<Object?, Object?>)
          .toList();
      expect(progressArgs.map((a) => a['fileName']), [
        'first.bin',
        'first.bin',
        'second.bin',
      ]);
      expect(progressArgs.map((a) => a['subtitle']), [
        'Uploading (1/2)…',
        'Uploading (1/2) · 50%',
        'Uploading (2/2) · 51%',
      ]);

      iosCalls.clear();
      bgCalls.clear();
      final cancel = CancelToken();
      await expectLater(
        TransferNotification.runUpload(
          label: 'archive.zip',
          completeTarget: 'archive.zip',
          fileCount: 1,
          cancel: cancel,
          body: (_) async {
            cancel.cancel();
            cancel.throwIfCancelled();
          },
        ),
        throwsA(isA<TransferCancelled>()),
      );
      expect(iosCalls.map((c) => c.method), [
        'showProgress',
        'cancelNotification',
      ]);
      expect(bgCalls.map((c) => c.method), ['begin', 'end']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(liveActivityChannel, null);
      messenger.setMockMethodCallHandler(backgroundChannel, null);
      messenger.setMockMethodCallHandler(notificationsChannel, null);
    }
  });
}
