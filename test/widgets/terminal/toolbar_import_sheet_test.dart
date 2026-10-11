import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/toolbar_layout.dart';
import 'package:termphin/services/settings/toolbar_share_link.dart';
import 'package:termphin/widgets/terminal/toolbar_import_sheet.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  final share = ToolbarShare(
    name: 'Claude Code',
    layout: ToolbarLayout(
      order: [
        'esc',
        'tab',
        toolbarCustomActionId(text: '/compact', appendEnter: true),
        toolbarCustomActionId(text: '/add '),
        toolbarCustomActionId(text: '\u001b\u001b', label: 'Esc Esc'),
        ...List.filled(5, ''),
        'f1',
        ...List.filled(9, ''),
      ],
      columns: 5,
      rows: 2,
      pages: 2,
    ),
    droppedKeys: 1,
  );

  Future<void> open(WidgetTester tester) async {
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showToolbarImportSheet(context, share),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the layout and every text key are there before adding', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.byKey(const ValueKey('importPreviewPage-0')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('importPreviewPage-0')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('importPreviewPage-1')), findsOneWidget);

    expect(
      find.text(
        '${t.toolbar.importTextKeys(n: 3)} · ${t.toolbar.importPressEnter(n: 1)}',
      ),
      findsOneWidget,
    );
    expect(find.text(t.toolbar.importEnterNote), findsOneWidget);
    expect(find.text(t.toolbar.importDropped(count: 1)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toolbarImportTextKeys')));
    await tester.pumpAndSettle();
    expect(find.text('/compact'), findsOneWidget);
    expect(find.text('/add '), findsOneWidget);
    expect(find.text('[Esc][Esc]'), findsOneWidget);
    expect(find.text(t.toolbar.importEnter), findsOneWidget);

    expect(toolbarSettings.profiles.value.profiles, hasLength(1));

    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final sheet = tester.getRect(find.byType(ToolbarImportSheet));
    expect(sheet.height, lessThanOrEqualTo(screen * 0.6 + 0.5));
  });

  testWidgets('add puts it beside the others without switching to it', (
    tester,
  ) async {
    final before = toolbarSettings.profiles.value.activeId;
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('toolbarImportAdd')));
    await tester.pumpAndSettle();

    final profiles = toolbarSettings.profiles.value;
    expect(profiles.profiles, hasLength(2));
    expect(profiles.profiles.last.name, 'Claude Code');
    expect(profiles.profiles.last.layout, share.layout);
    expect(profiles.activeId, before);
    expect(find.text(t.toolbar.importAdded), findsOneWidget);
  });

  testWidgets('add and use hands the toolbar to it', (tester) async {
    await open(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('toolbarImportAddAndUse')),
    );
    await tester.tap(find.byKey(const ValueKey('toolbarImportAddAndUse')));
    await tester.pumpAndSettle();

    final profiles = toolbarSettings.profiles.value;
    expect(profiles.active.name, 'Claude Code');
    expect(toolbarSettings.layout.value, share.layout);
  });
}
