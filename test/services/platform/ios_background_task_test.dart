import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/platform/ios_background_task.dart';

/// Pins the behaviour of IOSBackgroundTask.guard across platforms.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.termphin.termphin/background_task');

  late List<MethodCall> recordedCalls;
  Future<Object?> Function(MethodCall call)? mockHandler;

  setUp(() {
    recordedCalls = [];
    mockHandler = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recordedCalls.add(call);
          return mockHandler?.call(call);
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('off iOS', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test(
      'runs action once, returns value, and makes no channel call',
      () async {
        var runs = 0;
        final result = await IOSBackgroundTask.guard('sftp_save', () async {
          runs++;
          return 'success';
        });

        expect(runs, 1);
        expect(result, 'success');
        expect(recordedCalls, isEmpty);
      },
    );

    test('rethrows action errors and makes no channel call', () async {
      await expectLater(
        () => IOSBackgroundTask.guard(
          'sftp_save',
          () async => throw StateError('action failed'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(recordedCalls, isEmpty);
    });
  });

  group('on iOS', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    test('calls begin then end carrying the token begin returned', () async {
      const grantToken = 42;
      mockHandler = (call) async {
        if (call.method == 'begin') return grantToken;
        if (call.method == 'end') return null;
        return null;
      };

      final result = await IOSBackgroundTask.guard('sftp_save', () async {
        return 'downloaded';
      });

      expect(result, 'downloaded');
      expect(recordedCalls.map((c) => c.method).toList(), ['begin', 'end']);
      expect(recordedCalls[0].arguments, {'name': 'sftp_save'});
      expect(recordedCalls[1].arguments, {'token': grantToken});
    });

    test('calls end even when the action throws', () async {
      const grantToken = 73;
      mockHandler = (call) async {
        if (call.method == 'begin') return grantToken;
        if (call.method == 'end') return null;
        return null;
      };

      await expectLater(
        () => IOSBackgroundTask.guard(
          'sftp_save',
          () async => throw StateError('disk full'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(recordedCalls.map((c) => c.method).toList(), ['begin', 'end']);
      expect(recordedCalls[1].arguments, {'token': grantToken});
    });

    test(
      'runs action and does not call end when begin throws MissingPluginException',
      () async {
        mockHandler = (call) async {
          if (call.method == 'begin') {
            throw MissingPluginException('Not implemented on host');
          }
          return null;
        };

        var actionRan = false;
        final result = await IOSBackgroundTask.guard('sftp_save', () async {
          actionRan = true;
          return 'unprotected_result';
        });

        expect(actionRan, isTrue);
        expect(result, 'unprotected_result');
        expect(recordedCalls.map((c) => c.method).toList(), ['begin']);
      },
    );
  });
}
