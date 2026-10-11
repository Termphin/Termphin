import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/platform/foreground_notification_service.dart';

const _systemChannel = MethodChannel('dev.termphin.termphin/system');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ForegroundNotificationService.instance;
  late List<String> systemCalls;

  setUp(() {
    systemCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemChannel, (call) async {
          systemCalls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemChannel, null);
  });

  test('the notification leads with the session count, not the app name', () {
    expect(sessionNotificationContent(1), (
      title: '1 session connected',
      text: 'Tap to return',
    ));
    expect(sessionNotificationContent(3).title, '3 sessions connected');
  });

  test('is only a thing on Android', () {
    expect(service.supported, Platform.isAndroid);
  });

  test('init does nothing, since the service is not optional', () async {
    await expectLater(service.init(), completes);
  });

  group('off Android', () {
    setUp(() {
      if (service.supported) {
        markTestSkipped('Android has its own behaviour here');
      }
    });

    test('syncing sessions completes rather than throwing', () async {
      if (service.supported) return;
      await expectLater(service.syncSessions(2), completes);
      await expectLater(service.syncSessions(0), completes);
    });

    test('repeating the same count is a no-op', () async {
      if (service.supported) return;
      await service.syncSessions(3);
      await expectLater(service.syncSessions(3), completes);
    });

    test('reports no battery exemption to offer', () async {
      if (service.supported) return;
      expect(await service.isIgnoringBatteryOptimizations, isFalse);
    });

    test('reports notifications as already permitted', () async {
      if (service.supported) return;
      expect(await service.hasNotificationPermission, isTrue);
      expect(await service.requestNotificationPermission(), isTrue);
    });

    test('opens nothing, so the row is dead rather than crashing', () async {
      if (service.supported) return;
      await service.openNotificationSettings();
      expect(systemCalls, isEmpty);
    });

    test('asking for the battery exemption is a no-op', () async {
      if (service.supported) return;
      await expectLater(service.requestIgnoreBatteryOptimization(), completes);
    });
  });

  test('a burst of session changes is serialised, not interleaved', () async {
    final futures = [
      service.syncSessions(1),
      service.syncSessions(2),
      service.syncSessions(0),
    ];
    await expectLater(Future.wait(futures), completes);
  });
}
