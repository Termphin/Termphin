import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/settings/floating_dock_settings.dart';
import 'package:termphin/widgets/terminal/floating_action_dock.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await floatingDockSettings.load();
  });

  Widget dockIn(Size area) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: area,
        child: Stack(children: [FloatingActionDock(onTap: () {})]),
      ),
    ),
  );

  testWidgets('lays out in an area shorter than the button and its margins', (
    tester,
  ) async {
    await tester.pumpWidget(dockIn(const Size(400, 40)));

    expect(tester.takeException(), isNull);
  });
}
