import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/terminal/terminal_alerts.dart';
import 'package:termphin/services/terminal/terminal_notification.dart';

void main() {
  late List<TerminalAlert> posted;
  late bool enabled;
  late bool foreground;
  late String? active;
  late DateTime now;
  late TerminalAlerts alerts;

  setUp(() {
    posted = [];
    enabled = true;
    foreground = true;
    active = 'front';
    now = DateTime(2026, 11, 13, 20);
    alerts = TerminalAlerts(
      post: posted.add,
      enabled: () => enabled,
      isForeground: () => foreground,
      activeSessionId: () => active,
    );
  });

  void handle(String sessionId, TerminalNotification notification) => withClock(
    Clock.fixed(now),
    () => alerts.handle(
      sessionId: sessionId,
      sessionName: 'devbox',
      notification: notification,
    ),
  );

  const done = TerminalNotification(title: 'Claude is waiting for your input');

  test('a session in another tab is announced, under its machine', () {
    handle('back', done);

    expect(posted, [
      (
        sessionId: 'back',
        title: 'devbox',
        body: 'Claude is waiting for your input',
      ),
    ]);
  });

  test('the session on screen is not: its user has seen it', () {
    handle('front', done);

    expect(posted, isEmpty);
  });

  test(
    'with the app in the background, even the session last on screen is',
    () {
      foreground = false;

      handle('front', done);

      expect(posted, hasLength(1));
    },
  );

  test('a title and a body are kept as the program gave them', () {
    handle('back', const TerminalNotification(title: 'Build', body: 'failed'));

    expect(posted.single.title, 'Build');
    expect(posted.single.body, 'failed');
  });

  test('switched off, nothing is', () {
    enabled = false;

    handle('back', done);

    expect(posted, isEmpty);
  });

  test('a program asking in a loop gets one per quiet period', () {
    handle('back', done);
    now = now.add(const Duration(seconds: 1));
    handle('back', done);
    handle('other', done);
    now = now.add(const Duration(seconds: 3));
    handle('back', done);

    expect(
      [for (final alert in posted) alert.sessionId],
      ['back', 'other', 'back'],
    );
  });
}
