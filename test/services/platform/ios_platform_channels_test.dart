import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/platform/foreground_notification_service.dart';
import 'package:termphin/services/sftp/download_location.dart';
import 'package:termphin/services/sftp/download_service.dart';
import 'package:termphin/services/ssh/local_network_permission.dart';

/// Pins that no Android-only method channel calls escape on iOS.
///
/// Any newly added unguarded channel call must fail this suite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const systemChannel = MethodChannel('dev.termphin.termphin/system');
  const downloadsChannel = MethodChannel('dev.termphin.termphin/downloads');
  const localNetworkChannel = MethodChannel(
    'dev.termphin.termphin/local_network',
  );

  const localNotificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  late List<String> recordedCalls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    DownloadLocation.instance.invalidateCache();
    recordedCalls = [];

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(systemChannel, (call) async {
      recordedCalls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(downloadsChannel, (call) async {
      recordedCalls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(localNetworkChannel, (call) async {
      recordedCalls.add(call.method);
      return null;
    });

    messenger.setMockMethodCallHandler(localNotificationsChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'checkPermissions':
          return <String, dynamic>{'isEnabled': true};
        case 'requestPermissions':
          return true;
        case 'openAppNotificationSettings':
          return null;
        default:
          return null;
      }
    });

    messenger.setMockMethodCallHandler(urlLauncherChannel, (call) async {
      switch (call.method) {
        case 'canLaunch':
          return true;
        case 'launch':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DownloadLocation.instance.invalidateCache();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(systemChannel, null);
    messenger.setMockMethodCallHandler(downloadsChannel, null);
    messenger.setMockMethodCallHandler(localNetworkChannel, null);
    messenger.setMockMethodCallHandler(localNotificationsChannel, null);
    messenger.setMockMethodCallHandler(urlLauncherChannel, null);
  });

  group('ForegroundNotificationService on iOS', () {
    test('syncing active sessions makes no channel calls', () async {
      await ForegroundNotificationService.instance.syncSessions(1);
      await ForegroundNotificationService.instance.syncSessions(0);
      expect(recordedCalls, isEmpty);
    });

    test('battery optimization checks make no channel calls', () async {
      final ignoring = await ForegroundNotificationService
          .instance
          .isIgnoringBatteryOptimizations;
      expect(ignoring, isFalse);
      await ForegroundNotificationService.instance
          .requestIgnoreBatteryOptimization();
      expect(recordedCalls, isEmpty);
    });

    test(
      'notification permission checks report granted without channel calls',
      () async {
        final permitted = await ForegroundNotificationService
            .instance
            .hasNotificationPermission;
        expect(permitted, isTrue);

        final requested = await ForegroundNotificationService.instance
            .requestNotificationPermission();
        expect(requested, isTrue);

        await ForegroundNotificationService.instance.openNotificationSettings();
        expect(recordedCalls, isEmpty);
      },
    );
  });

  group('LocalNetworkPermission on iOS', () {
    test(
      'enforcement and grant queries report status without channel calls',
      () async {
        final enforced = await LocalNetworkPermission.instance.isEnforced;
        expect(enforced, isFalse);

        final granted = await LocalNetworkPermission.instance.isGranted;
        expect(granted, isTrue);

        expect(recordedCalls, isEmpty);
      },
    );

    test('permission requests grant without channel calls', () async {
      final result = await LocalNetworkPermission.instance.request();
      expect(result, LocalNetworkPermissionResult.granted);
      expect(recordedCalls, isEmpty);
    });

    test(
      'opening app settings launches settings without channel calls',
      () async {
        await LocalNetworkPermission.instance.openAppSettings();
        expect(recordedCalls, isEmpty);
      },
    );
  });

  group('DownloadLocation on iOS', () {
    test('picking a folder returns null without channel calls', () async {
      final folder = await DownloadLocation.instance.pick();
      expect(folder, isNull);
      expect(recordedCalls, isEmpty);
    });

    test(
      'querying current location reads preferences without channel calls',
      () async {
        final folder = await DownloadLocation.instance.current();
        expect(folder, isNull);
        expect(recordedCalls, isEmpty);
      },
    );

    test('clearing download location touches no channel calls', () async {
      await DownloadLocation.instance.clear();
      expect(recordedCalls, isEmpty);
    });

    test('forgetting download location touches no channel calls', () async {
      await DownloadLocation.instance.forget();
      expect(recordedCalls, isEmpty);
    });
  });

  group('DownloadService on iOS', () {
    test(
      'opening a nonexistent saved download makes no channel calls',
      () async {
        const download = SavedDownload(
          fileName: 'absent.txt',
          uri: '/tmp/termphin_nonexistent_download_target.txt',
        );
        await DownloadService.openSavedDownload(download);
        expect(recordedCalls, isEmpty);
      },
    );
  });

  test('exercising every guarded method leaves recorded calls empty', () async {
    final foreground = ForegroundNotificationService.instance;
    await foreground.syncSessions(1);
    await foreground.syncSessions(0);
    expect(await foreground.isIgnoringBatteryOptimizations, isFalse);
    await foreground.requestIgnoreBatteryOptimization();
    expect(await foreground.hasNotificationPermission, isTrue);
    expect(await foreground.requestNotificationPermission(), isTrue);
    await foreground.openNotificationSettings();

    final localNetwork = LocalNetworkPermission.instance;
    expect(await localNetwork.isEnforced, isFalse);
    expect(await localNetwork.isGranted, isTrue);
    expect(await localNetwork.request(), LocalNetworkPermissionResult.granted);
    await localNetwork.openAppSettings();

    final downloadLocation = DownloadLocation.instance;
    expect(await downloadLocation.pick(), isNull);
    expect(await downloadLocation.current(), isNull);
    await downloadLocation.clear();
    await downloadLocation.forget();

    const missingDownload = SavedDownload(
      fileName: 'absent.txt',
      uri: '/tmp/termphin_nonexistent_download_target.txt',
    );
    await DownloadService.openSavedDownload(missingDownload);

    expect(recordedCalls, isEmpty);
  });
}
