import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/widgets/ui/group_picker_sheet.dart';
import 'package:termphin/widgets/ui/selection_action_bar.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t = AppLocale.en.buildSync();

  testWidgets('the bar counts the selection and fires each action', (
    tester,
  ) async {
    var moved = 0;
    var deleted = 0;
    var cleared = 0;

    await pumpTestApp(
      tester,
      Scaffold(
        bottomNavigationBar: SelectionActionBar(
          count: 3,
          onMove: () => moved++,
          onDelete: () => deleted++,
          onClear: () => cleared++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(t.selection.countSelected(n: 3, count: 3)),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip(t.selection.moveToGroup));
    await tester.tap(find.byTooltip(t.common.delete));
    await tester.tap(find.byTooltip(t.selection.clear));
    await tester.pumpAndSettle();

    expect(moved, 1);
    expect(deleted, 1);
    expect(cleared, 1);
  });

  testWidgets('an empty selection cannot be moved or deleted', (tester) async {
    var fired = 0;
    await pumpTestApp(
      tester,
      Scaffold(
        bottomNavigationBar: SelectionActionBar(
          count: 0,
          onMove: () => fired++,
          onDelete: () => fired++,
          onClear: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(t.selection.moveToGroup));
    await tester.tap(find.byTooltip(t.common.delete));
    await tester.pumpAndSettle();

    expect(fired, 0);
  });

  testWidgets('the bar slides away once the selection is cleared', (
    tester,
  ) async {
    Widget host({required bool selecting}) => Scaffold(
      body: SelectionActionHost(
        bar: selecting
            ? SelectionActionBar(
                count: 1,
                onMove: () {},
                onDelete: () {},
                onClear: () {},
              )
            : null,
        child: const SizedBox.expand(),
      ),
    );

    await pumpTestApp(tester, host(selecting: true));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionActionBar), findsOneWidget);

    await pumpTestApp(tester, host(selecting: false));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionActionBar), findsNothing);
  });

  testWidgets('the move sheet returns a group and skips the current one', (
    tester,
  ) async {
    String? picked;

    await pumpTestApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                picked = await showGroupPickerSheet(
                  context,
                  groups: const [
                    ProfileGroup(name: 'General'),
                    ProfileGroup(name: 'Production'),
                  ],
                  current: 'General',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final general = tester.widget<ListTile>(
      find.ancestor(
        of: find.text(t.groups.general),
        matching: find.byType(ListTile),
      ),
    );
    expect(general.enabled, isFalse);

    await tester.tap(find.text('Production'));
    await tester.pumpAndSettle();

    expect(picked, 'Production');
  });
}
