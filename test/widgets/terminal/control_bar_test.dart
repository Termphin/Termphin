import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/models/session_control.dart';
import 'package:termphin/services/realtime/presence_device.dart';
import 'package:termphin/widgets/terminal/control_bar.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets('names the device in control and takes control on a tap', (
    tester,
  ) async {
    var taken = 0;
    await pumpTestApp(
      tester,
      Scaffold(
        body: ControlBar(
          control: const SessionControl(
            holds: false,
            columns: 200,
            rows: 50,
            device: PresenceDevice(
              id: 'abc',
              kind: PresenceDeviceKind.desktop,
              name: 'MacBook',
            ),
          ),
          onTake: () => taken++,
        ),
      ),
    );

    expect(find.text('MacBook is in control'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('takeControl')));
    expect(taken, 1);
  });

  testWidgets('says another device when the holder never said which', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: ControlBar(
          control: const SessionControl(holds: false, columns: 80, rows: 24),
          onTake: () {},
        ),
      ),
    );

    expect(find.text('Another device is in control'), findsOneWidget);
  });
}
