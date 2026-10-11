import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/active_session.dart';
import 'package:termphin/services/settings/sftp_settings.dart';
import 'package:termphin/widgets/sftp/sftp_browser_view.dart';
import 'package:termphin/widgets/sftp/sftp_file_row.dart';
import 'package:termphin/widgets/sftp/sftp_shortcuts.dart';
import 'package:termphin/widgets/window/app_menu.dart';

import '../../support/fixtures.dart';
import '../../support/sftp_fakes.dart';
import '../../support/test_app.dart';

const _desktop = TargetPlatformVariant({TargetPlatform.linux});

Future<void> _pumpBrowser(WidgetTester tester) async {
  final tree = FakeSftpTree({
    '/home/user': [
      sftpDir('projects'),
      sftpFile('a.txt', size: 300),
      sftpFile('b.txt', size: 100),
      sftpFile('c.txt', size: 200),
    ],
    '/home/user/projects': [sftpFile('inside.txt')],
  });
  final session = ActiveSessionView(
    id: 'session-1',
    profile: profileFixture(),
    connectedAt: DateTime.now(),
    sshService: FakeSftpSshService(FakeSftpClient(tree)),
  );
  await pumpTestApp(tester, Scaffold(body: SftpBrowserView(session: session)));
  await tester.pumpAndSettle();
}

SftpFileRow _row(WidgetTester tester, String name) =>
    tester.widget<SftpFileRow>(
      find.ancestor(of: find.text(name), matching: find.byType(SftpFileRow)),
    );

List<String> _selected(WidgetTester tester) => [
  for (final row in tester.widgetList<SftpFileRow>(find.byType(SftpFileRow)))
    if (row.isSelected) row.item.filename,
];

/// Clicks [name] and lets the double-click window close, so the next click
/// on the same row is a click of its own.
Future<void> _click(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sftpShowHiddenSetting.load();
    await sftpSortFieldSetting.load();
    await sftpSortDescendingSetting.load();
  });

  testWidgets('a click selects the row and leaves the folder alone', (
    tester,
  ) async {
    await _pumpBrowser(tester);

    await _click(tester, 'projects');

    expect(_selected(tester), ['projects']);
    expect(_row(tester, 'projects').isCursor, isTrue);
    expect(find.text('a.txt'), findsOneWidget);
    expect(find.textContaining('selected'), findsNothing);
  }, variant: _desktop);

  testWidgets('a second click in time opens the row', (tester) async {
    await _pumpBrowser(tester);

    await tester.tap(find.text('projects'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('projects'));
    await tester.pumpAndSettle();

    expect(find.text('inside.txt'), findsOneWidget);
    expect(find.text('a.txt'), findsNothing);
  }, variant: _desktop);

  testWidgets('a slow second click is not a double click', (tester) async {
    await _pumpBrowser(tester);

    await _click(tester, 'projects');
    await _click(tester, 'projects');

    expect(find.text('a.txt'), findsOneWidget);
    expect(_selected(tester), ['projects']);
  }, variant: _desktop);

  testWidgets('the arrows move the selection, Shift extends it', (
    tester,
  ) async {
    await _pumpBrowser(tester);
    await _click(tester, 'a.txt');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_selected(tester), ['b.txt']);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_selected(tester), ['b.txt', 'c.txt']);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(_selected(tester), ['a.txt', 'b.txt']);
  }, variant: _desktop);

  testWidgets('Home and End go to the ends, Shift+End takes the rest', (
    tester,
  ) async {
    await _pumpBrowser(tester);
    await _click(tester, 'a.txt');

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(_selected(tester), ['c.txt']);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(_selected(tester), ['projects']);
    expect(_row(tester, 'projects').isCursor, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(_selected(tester), ['projects', 'a.txt', 'b.txt', 'c.txt']);
  }, variant: _desktop);

  testWidgets('Ctrl with the arrows moves the cursor past the selection, and '
      'Space adds the row it is on', (tester) async {
    await _pumpBrowser(tester);
    await _click(tester, 'a.txt');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(_selected(tester), ['a.txt']);
    expect(_row(tester, 'c.txt').isCursor, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(_selected(tester), ['a.txt', 'c.txt']);
  }, variant: _desktop);

  testWidgets('Enter opens the row the cursor is on', (tester) async {
    await _pumpBrowser(tester);
    await _click(tester, 'projects');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('inside.txt'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('Ctrl+click adds a row, Shift+click takes the range', (
    tester,
  ) async {
    await _pumpBrowser(tester);
    await _click(tester, 'a.txt');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await _click(tester, 'c.txt');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(_selected(tester), ['a.txt', 'c.txt']);

    await _click(tester, 'projects');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _click(tester, 'b.txt');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(_selected(tester), ['projects', 'a.txt', 'b.txt']);
  }, variant: _desktop);

  testWidgets('Escape drops a selection of one', (tester) async {
    await _pumpBrowser(tester);
    await _click(tester, 'a.txt');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(_selected(tester), isEmpty);
  }, variant: _desktop);

  testWidgets('a column header sorts by it, and turns the order around on a '
      'second click', (tester) async {
    await _pumpBrowser(tester);

    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    expect(sftpSortFieldSetting.value, SftpSortField.size);
    expect(sftpSortDescendingSetting.value, isFalse);

    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    expect(sftpSortDescendingSetting.value, isTrue);

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(sftpSortFieldSetting.value, SftpSortField.name);
    expect(sftpSortDescendingSetting.value, isFalse);
  }, variant: _desktop);

  testWidgets('F7 asks for a new folder, Shift+F7 for a new file', (
    tester,
  ) async {
    await _pumpBrowser(tester);
    await _click(tester, 'a.txt');

    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.pumpAndSettle();
    expect(find.text('Folder name'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('File name'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('Ctrl+H shows and hides the hidden files', (tester) async {
    await _pumpBrowser(tester);
    await _click(tester, 'a.txt');
    expect(sftpShowHiddenSetting.value, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(sftpShowHiddenSetting.value, isTrue);
  }, variant: _desktop);

  testWidgets('the sort button is gone where the header sorts', (tester) async {
    await _pumpBrowser(tester);

    expect(find.byIcon(PhosphorIconsFill.sortAscending), findsNothing);
    expect(find.byType(SftpColumnHeader), findsOneWidget);
  }, variant: _desktop);

  testWidgets('the Files menu names each key and greys out what has nothing '
      'to act on', (tester) async {
    await _pumpBrowser(tester);
    final state = tester.state<SftpBrowserViewState>(
      find.byType(SftpBrowserView),
    );
    final t = Translations.of(tester.element(find.byType(SftpBrowserView)));
    AppMenuItem item(String label) => state
        .menus(t)
        .single
        .groups
        .expand((group) => group)
        .firstWhere((item) => item.label == label);

    expect(item('Rename').enabled, isFalse);
    expect(item('Delete').enabled, isFalse);
    expect(item('New folder').shortcut, SftpShortcuts.newFolder);
    expect(item('Show hidden files').checked, isFalse);

    await _click(tester, 'a.txt');
    expect(item('Rename').enabled, isTrue);
    expect(item('Rename').shortcut, SftpShortcuts.rename);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(item('Rename').enabled, isFalse);
    expect(item('Delete').enabled, isTrue);
  }, variant: _desktop);

  testWidgets('there is no pull to refresh; F5 lists the folder again', (
    tester,
  ) async {
    final client = FakeSftpClient(
      FakeSftpTree({
        '/home/user': [sftpFile('a.txt')],
      }),
    );
    final session = ActiveSessionView(
      id: 'session-1',
      profile: profileFixture(),
      connectedAt: DateTime.now(),
      sshService: FakeSftpSshService(client),
    );
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: session)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RefreshIndicator), findsNothing);

    client.tree.children['/home/user']!.add(sftpFile('new.txt'));
    await _click(tester, 'a.txt');
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();

    expect(find.text('new.txt'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('a phone has no header and still opens a folder on one tap', (
    tester,
  ) async {
    await _pumpBrowser(tester);

    expect(find.byType(SftpColumnHeader), findsNothing);
    expect(find.byIcon(PhosphorIconsFill.sortAscending), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    await tester.tap(find.text('projects'));
    await tester.pumpAndSettle();

    expect(find.text('inside.txt'), findsOneWidget);
  });
}
