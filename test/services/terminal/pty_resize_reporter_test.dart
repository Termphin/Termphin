import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/terminal/pty_resize_reporter.dart';

void main() {
  const settle = Duration(milliseconds: 120);

  late List<(int, int)> sent;
  late PtyResizeReporter reporter;

  setUp(() {
    sent = [];
    reporter = PtyResizeReporter(send: (cols, rows) => sent.add((cols, rows)));
  });

  test('only the size the layout settles on is sent', () {
    fakeAsync((async) {
      reporter
        ..report(80, 40)
        ..report(80, 35)
        ..report(80, 30);
      async.elapse(settle);

      expect(sent, [(80, 30)]);
    });
  });

  test('the same size twice sends nothing new', () {
    fakeAsync((async) {
      reporter.report(80, 30);
      async.elapse(settle);
      reporter.report(80, 30);
      async.elapse(settle);

      expect(sent, [(80, 30)]);
    });
  });

  test(
    'settling back on the server size nudges it so the program repaints',
    () {
      fakeAsync((async) {
        reporter.report(80, 30);
        async.elapse(settle);
        sent.clear();

        reporter
          ..report(80, 45)
          ..report(80, 30);
        async.elapse(settle);

        expect(sent, [(80, 29), (80, 30)]);
      });
    },
  );

  test('a one-row terminal is nudged up rather than to zero rows', () {
    fakeAsync((async) {
      reporter.report(80, 1);
      async.elapse(settle);
      sent.clear();

      reporter
        ..report(80, 5)
        ..report(80, 1);
      async.elapse(settle);

      expect(sent, [(80, 2), (80, 1)]);
    });
  });

  test('a real change is sent without a nudge', () {
    fakeAsync((async) {
      reporter.report(80, 30);
      async.elapse(settle);
      sent.clear();

      reporter.report(100, 30);
      async.elapse(settle);

      expect(sent, [(100, 30)]);
    });
  });

  test('nothing is sent after dispose', () {
    fakeAsync((async) {
      reporter
        ..report(80, 30)
        ..dispose();
      async.elapse(settle);

      expect(sent, isEmpty);
    });
  });
}
