import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/terminal/terminal_alerts.dart';
import 'package:termphin/services/terminal/terminal_notification.dart';

void main() {
  late List<TerminalAlert> posted;
  late bool enabled;
  late bool quiet;
  late bool lines;
  late bool foreground;
  late String? active;
  late DateTime now;
  late TerminalAlerts alerts;

  setUp(() {
    posted = [];
    enabled = true;
    quiet = true;
    lines = true;
    foreground = true;
    active = 'front';
    now = DateTime(2026, 11, 13, 20);
    alerts = TerminalAlerts(
      post: posted.add,
      allows: (notification) => switch (notification.kind) {
        null => enabled,
        TerminalNoticeKind.quiet => quiet,
        TerminalNoticeKind.finished => true,
      },
      quoteLines: () => lines,
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

  void visibilityChanged() =>
      withClock(Clock.fixed(now), alerts.visibilityChanged);

  const done = TerminalNotification(title: 'Claude is waiting for your input');

  const quietNotice = TerminalNotification(
    title: 'Waiting',
    body: 'Do you want to proceed? [y/N]',
    kind: TerminalNoticeKind.quiet,
    plain: 'after 35s',
  );

  const finishedNotice = TerminalNotification(
    title: 'Complete!',
    body: 'Build ok',
    kind: TerminalNoticeKind.finished,
    plain: 'after 35s',
  );

  void leaveFront() {
    visibilityChanged();
    active = 'back';
    visibilityChanged();
  }

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

  test(
    'a quiet notice is dropped when its switch is off, a program one is not',
    () {
      quiet = false;
      const notice = TerminalNotification(
        title: 'Waiting',
        body: 'Do you want to proceed? [y/N]',
        kind: TerminalNoticeKind.quiet,
        plain: 'after 35s',
      );

      handle('back', notice);
      handle('other', done);

      expect(posted.map((alert) => alert.sessionId), ['other']);
    },
  );

  test('with lines on, a notice quotes the line it was given', () {
    handle(
      'back',
      const TerminalNotification(
        title: 'Complete!',
        body: 'Build ok',
        kind: TerminalNoticeKind.finished,
        plain: 'after 35s',
      ),
    );

    expect(posted.single.body, 'Build ok');
  });

  test('with lines off, a notice is announced without the line it quotes', () {
    lines = false;

    handle(
      'back',
      const TerminalNotification(
        title: 'Complete!',
        body: 'Build ok',
        kind: TerminalNoticeKind.finished,
        plain: 'after 35s',
      ),
    );

    expect(posted.single.title, 'Complete!');
    expect(posted.single.body, 'after 35s');
  });

  test('with lines off, a program notification keeps its body', () {
    lines = false;

    handle('back', const TerminalNotification(title: 'Build', body: 'failed'));

    expect(posted.single.body, 'failed');
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

  test('a quiet notice from a session left 5 s ago is not news', () {
    visibilityChanged();
    leaveFront();
    now = now.add(const Duration(seconds: 5));

    handle('front', quietNotice);

    expect(posted, isEmpty);
  });

  test('a quiet notice from a session left 12 s ago is posted', () {
    visibilityChanged();
    leaveFront();
    now = now.add(const Duration(seconds: 12));

    handle('front', quietNotice);

    expect(posted.single.sessionId, 'front');
  });

  test('a finished notice from a session left 2 s ago is not news', () {
    visibilityChanged();
    leaveFront();
    now = now.add(const Duration(seconds: 2));

    handle('front', finishedNotice);

    expect(posted, isEmpty);
  });

  test('a finished notice from a session left 6 s ago is posted', () {
    visibilityChanged();
    leaveFront();
    now = now.add(const Duration(seconds: 6));

    handle('front', finishedNotice);

    expect(posted.single.sessionId, 'front');
  });

  test('a program notification from a session left 2 s ago is posted', () {
    visibilityChanged();
    leaveFront();
    now = now.add(const Duration(seconds: 2));

    handle('front', const TerminalNotification(title: 'Build', body: 'failed'));

    expect(posted.single.sessionId, 'front');
  });

  test('forgetting a session clears when it was last seen', () {
    visibilityChanged();
    leaveFront();
    alerts.forget('front');
    now = now.add(const Duration(seconds: 2));

    handle('front', finishedNotice);

    expect(posted.single.sessionId, 'front');
  });
}
