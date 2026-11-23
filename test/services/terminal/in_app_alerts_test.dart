import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/terminal/in_app_alerts.dart';
import 'package:termphin/services/terminal/terminal_alerts.dart';

void main() {
  const alert = (
    sessionId: 's',
    title: 'build finished',
    body: 'done',
    source: null,
  );

  InAppAlerts alerts({
    bool foreground = true,
    bool enabled = true,
    bool inApp = true,
    bool Function(TerminalAlert alert)? present,
  }) => InAppAlerts(
    isForeground: () => foreground,
    enabled: () => enabled,
    inApp: () => inApp,
  )..present = present;

  test('in front, the app shows it and no system notification is needed', () {
    final shown = <TerminalAlert>[];
    final subject = alerts(
      present: (alert) {
        shown.add(alert);
        return true;
      },
    );

    expect(subject.handle(alert), isTrue);
    expect(shown, [alert]);
  });

  test('in the background it is left to the system, whatever the settings', () {
    expect(
      alerts(foreground: false, present: (_) => true).handle(alert),
      isFalse,
    );
    expect(alerts(foreground: false, enabled: false).handle(alert), isFalse);
  });

  test('turned off for the open app, it is dropped without a notification', () {
    var shown = false;
    final subject = alerts(enabled: false, present: (_) => shown = true);

    expect(subject.handle(alert), isTrue);
    expect(shown, isFalse);
  });

  test('set to the system style, the system shows it', () {
    var shown = false;
    final subject = alerts(inApp: false, present: (_) => shown = true);

    expect(subject.handle(alert), isFalse);
    expect(shown, isFalse);
  });

  test('when the app cannot show it, the system does', () {
    expect(alerts().handle(alert), isFalse);
    expect(alerts(present: (_) => false).handle(alert), isFalse);
  });
}
