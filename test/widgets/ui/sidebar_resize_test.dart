import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/settings/sidebar_settings.dart';
import 'package:termphin/widgets/ui/nav_rail.dart';

import '../../support/test_app.dart';

const _desktop = TargetPlatformVariant({TargetPlatform.linux});

Widget _rail() => Scaffold(
  body: Row(
    children: [
      SidebarBuilder(
        builder: (context, collapsed) => SizedBox(
          key: const ValueKey('rail'),
          width: navRailWidth(collapsed),
          height: 400,
        ),
      ),
    ],
  ),
);

double _railWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('rail'))).width;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sidebarCollapsedSetting.load();
    await sidebarWidthSetting.load();
  });

  testWidgets('dragging the edge widens the rail and keeps the width', (
    tester,
  ) async {
    await pumpTestApp(tester, _rail());
    expect(_railWidth(tester), 240);

    await tester.dragFrom(
      const Offset(238, 200),
      const Offset(80, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(_railWidth(tester), greaterThan(280));
    expect(sidebarWidthSetting.value, _railWidth(tester));
    final stored = await SharedPreferences.getInstance();
    expect(stored.getDouble(kSidebarWidthPrefsKey), _railWidth(tester));
  }, variant: _desktop);

  testWidgets('the rail stops at its widest and its narrowest', (tester) async {
    await pumpTestApp(tester, _rail());

    await tester.dragFrom(
      const Offset(238, 200),
      const Offset(500, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(_railWidth(tester), kSidebarMaxWidth);

    await tester.dragFrom(
      const Offset(kSidebarMaxWidth - 2, 200),
      const Offset(-400, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(_railWidth(tester), kSidebarMinWidth);
  }, variant: _desktop);

  testWidgets('collapsed, the rail is its icons and has no edge to drag', (
    tester,
  ) async {
    await sidebarCollapsedSetting.set(true);
    await pumpTestApp(tester, _rail());

    await tester.dragFrom(
      const Offset(kNavRailCollapsedWidth - 2, 200),
      const Offset(80, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(_railWidth(tester), kNavRailCollapsedWidth);
    expect(sidebarWidthSetting.value, sidebarWidthSetting.fallback);
  }, variant: _desktop);

  testWidgets('a tablet keeps the fixed width whatever a desktop stored', (
    tester,
  ) async {
    await sidebarWidthSetting.set(360);
    await pumpTestApp(tester, _rail());

    expect(_railWidth(tester), kNavRailWidth);
  });
}
