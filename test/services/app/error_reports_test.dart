import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/app/error_reports.dart';

void main() {
  final time = DateTime.utc(2026, 10, 13, 9, 5, 7);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  group('ErrorReports', () {
    test('keeps the newest reports first, up to its capacity', () async {
      final reports = ErrorReports(capacity: 2);
      for (var i = 0; i < 3; i++) {
        await reports.record(StateError('error $i'), null, time: time);
      }
      expect(reports.reports.map((r) => r.message), [
        'Bad state: error 2',
        'Bad state: error 1',
      ]);
    });

    test(
      'counts the same error back to back instead of repeating it',
      () async {
        final reports = ErrorReports();
        final stack = StackTrace.current;
        await reports.record(StateError('same'), stack, time: time);
        await reports.record(StateError('same'), stack, time: time);
        await reports.record(StateError('other'), stack, time: time);
        expect(reports.reports.map((r) => (r.message, r.count)), [
          ('Bad state: other', 1),
          ('Bad state: same', 2),
        ]);
      },
    );

    test('skips a dropped socket, ordinary for an SSH client', () async {
      final reports = ErrorReports();
      await reports.record(const SocketException('closed'), null);
      expect(reports.reports, isEmpty);
    });

    test('cuts the stack to its frame limit', () async {
      final reports = ErrorReports(maxStackLines: 3);
      final stack = StackTrace.fromString(
        List.generate(10, (i) => '#$i frame').join('\n'),
      );
      await reports.record(StateError('deep'), stack, time: time);
      expect(reports.reports.single.stack, '#0 frame\n#1 frame\n#2 frame');
    });

    test('survives a restart and is gone after clearing', () async {
      final first = ErrorReports();
      await first.record(StateError('crash'), null, time: time);

      final restarted = ErrorReports();
      await restarted.load();
      expect(restarted.reports.single.message, 'Bad state: crash');
      expect(restarted.reports.single.time, time);

      await restarted.clear();
      final again = ErrorReports();
      await again.load();
      expect(again.reports, isEmpty);
    });

    test('a corrupt stored value reads as no reports', () async {
      SharedPreferences.setMockInitialValues({kErrorReportsPrefsKey: '{'});
      final reports = ErrorReports();
      await reports.load();
      expect(reports.reports, isEmpty);
    });

    test('exports the header and every report, newest first', () async {
      final reports = ErrorReports();
      await reports.record(StateError('old'), null, time: time);
      await reports.record(StateError('new'), null, time: time);
      expect(
        reports.export(header: 'Termphin 1.0.0'),
        'Termphin 1.0.0\n\n'
        '2026-10-13T09:05:07.000Z\nBad state: new\n\n'
        '2026-10-13T09:05:07.000Z\nBad state: old',
      );
    });

    test('records Flutter errors and still hands them on', () async {
      final reports = ErrorReports();
      final previousFlutterError = FlutterError.onError;
      final previousPlatformError = PlatformDispatcher.instance.onError;
      final handedOn = <Object>[];
      FlutterError.onError = (details) => handedOn.add(details.exception);
      PlatformDispatcher.instance.onError = (error, stack) {
        handedOn.add(error);
        return true;
      };
      try {
        reports.install();
        FlutterError.onError!(
          FlutterErrorDetails(exception: StateError('widget')),
        );
        final handled = PlatformDispatcher.instance.onError!(
          StateError('async'),
          StackTrace.empty,
        );
        await pumpEventQueue();

        expect(handled, isTrue);
        expect(handedOn.map((e) => e.toString()), [
          'Bad state: widget',
          'Bad state: async',
        ]);
        expect(reports.reports.map((r) => r.message), [
          'Bad state: async',
          'Bad state: widget',
        ]);
      } finally {
        FlutterError.onError = previousFlutterError;
        PlatformDispatcher.instance.onError = previousPlatformError;
      }
    });
  });
}
