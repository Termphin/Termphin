import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:termphin/widgets/ui/settings_tile.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a destination pushes the screen it builds', (tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: SettingsTile(
          title: 'Row',
          destination: () => const Scaffold(body: Text('Detail')),
        ),
      ),
    );

    await tester.tap(find.text('Row'));
    await tester.pumpAndSettle();

    expect(find.text('Detail'), findsOneWidget);
  });

  testWidgets('onTap fires', (tester) async {
    var tapped = false;
    await pumpTestApp(
      tester,
      Scaffold(
        body: SettingsTile(title: 'Row', onTap: () => tapped = true),
      ),
    );

    await tester.tap(find.text('Row'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('a chevron trailing shows the caret icon', (tester) async {
    await pumpTestApp(
      tester,
      const Scaffold(
        body: SettingsTile(title: 'Row', onTap: _noop),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Icon && widget.icon == PhosphorIconsFill.caretRight,
      ),
      findsOneWidget,
    );
  });

  testWidgets('an external trailing shows the arrow-out icon', (tester) async {
    await pumpTestApp(
      tester,
      const Scaffold(
        body: SettingsTile(
          title: 'Row',
          trailing: SettingsTileTrailing.external,
          onTap: _noop,
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Icon && widget.icon == PhosphorIconsFill.arrowSquareOut,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a none trailing shows no icon', (tester) async {
    await pumpTestApp(
      tester,
      const Scaffold(
        body: SettingsTile(
          title: 'Row',
          trailing: SettingsTileTrailing.none,
          onTap: _noop,
        ),
      ),
    );

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.trailing, isNull);
  });

  testWidgets('a row with neither destination nor onTap is not tappable', (
    tester,
  ) async {
    await pumpTestApp(tester, const Scaffold(body: SettingsTile(title: 'Row')));

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.onTap, isNull);
  });

  testWidgets('toggling the switch calls onChanged', (tester) async {
    bool? value;
    await pumpTestApp(
      tester,
      Scaffold(
        body: SettingsSwitchTile(
          title: 'Switch',
          value: false,
          onChanged: (v) => value = v,
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(value, isTrue);
  });

  testWidgets('the key passed to SettingsSwitchTile is kept', (tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: SettingsSwitchTile(
          key: const ValueKey('mySwitch'),
          title: 'Switch',
          value: false,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('mySwitch')), findsOneWidget);
  });
}

void _noop() {}
