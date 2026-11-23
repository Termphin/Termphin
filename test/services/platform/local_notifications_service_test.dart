import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/platform/local_notifications_service.dart';

/// Pins where this service is allowed to act.
///
/// The transfer notifications stay iOS-only: Android posts its own from
/// DownloadChannel.kt alongside the bytes, so a second one from here would
/// double up. The session-drop notification is the exception - it has to work
/// on both, which is why `supported` gates the transfer methods and not the
/// whole class.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notificationsPluginChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  final service = LocalNotificationsService.instance;
  late List<String> recordedCalls;
  late bool notificationsEnabled;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    recordedCalls = [];
    notificationsEnabled = true;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsPluginChannel, (call) async {
          recordedCalls.add(call.method);
          if (call.method == 'areNotificationsEnabled') {
            return notificationsEnabled;
          }
          if (call.method == 'initialize') return true;
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsPluginChannel, null);
  });

  test('names the session after the title, as a push does', () {
    expect(
      titleWithSession('make deploy finished', 'api'),
      'make deploy finished · api',
    );
    expect(titleWithSession('Backup', null), 'Backup');
    expect(titleWithSession('Backup', ''), 'Backup');
    expect(titleWithSession('', 'api'), 'api');
  });

  test('is not supported off iOS', () {
    expect(service.supported, isFalse);
  });

  test('reports what Android says about the permission', () async {
    notificationsEnabled = true;
    expect(await service.hasPermission(), isTrue);

    notificationsEnabled = false;
    expect(await service.hasPermission(), isFalse);
  });

  test(
    'requesting permission returns true without channel calls off iOS',
    () async {
      expect(await service.requestPermission(), isTrue);
      expect(recordedCalls, isEmpty);
    },
  );

  test(
    'init does initialise on Android, since a session drop posts there',
    () async {
      await expectLater(service.init(), completes);
      expect(recordedCalls, contains('initialize'));
    },
  );

  test('a dropped session is announced on Android', () async {
    notificationsEnabled = true;
    await expectLater(service.showSessionDropped(name: 'build box'), completes);
    expect(recordedCalls, contains('show'));
  });

  test('a dropped session is not announced without the permission', () async {
    notificationsEnabled = false;
    await expectLater(service.showSessionDropped(name: 'build box'), completes);
    expect(recordedCalls, isNot(contains('show')));
  });

  test(
    'announcing a finished transfer makes no channel calls off iOS',
    () async {
      await expectLater(
        service.showTransferComplete(fileName: 'archive.tar', fileCount: 1),
        completes,
      );
      await expectLater(
        service.showTransferComplete(fileName: 'bundle', fileCount: 5),
        completes,
      );
      expect(recordedCalls, isEmpty);
    },
  );

  test('announcing a failed transfer makes no channel calls off iOS', () async {
    await expectLater(
      service.showTransferFailed(fileName: 'archive.tar'),
      completes,
    );
    expect(recordedCalls, isEmpty);
  });

  test('opening settings makes no channel calls off iOS', () async {
    await expectLater(service.openSettings(), completes);
    expect(recordedCalls, isEmpty);
  });

  group('on a Linux desktop', () {
    late _RecordingLinuxNotifications linux;
    late FlutterLocalNotificationsPlatform previous;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      previous = FlutterLocalNotificationsPlatform.instance;
      linux = _RecordingLinuxNotifications();
      FlutterLocalNotificationsPlatform.instance = linux;
    });

    tearDown(() {
      FlutterLocalNotificationsPlatform.instance = previous;
    });

    test('posts a terminal alert, which opens its session', () async {
      await service.showTerminalAlert(
        sessionId: 'session-7',
        title: 'build',
        body: 'done',
      );

      expect(linux.shown.single, ('build', 'done', 'session:session-7'));
    });

    test('posts a dropped session', () async {
      await service.showSessionDropped(name: 'prod');

      expect(linux.shown, hasLength(1));
    });
  });
}

class _RecordingLinuxNotifications
    extends LinuxFlutterLocalNotificationsPlugin {
  final shown = <(String?, String?, String?)>[];

  @override
  Future<bool?> initialize({
    required LinuxInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async => true;

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    LinuxNotificationDetails? notificationDetails,
    String? payload,
  }) async => shown.add((title, body, payload));
}
