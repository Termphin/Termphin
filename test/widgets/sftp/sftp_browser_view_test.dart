import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/active_session.dart';
import 'package:termphin/services/settings/sftp_settings.dart';
import 'package:termphin/widgets/sftp/sftp_browser_view.dart';

import '../../support/fixtures.dart';
import '../../support/sftp_fakes.dart';
import '../../support/test_app.dart';

/// Select all lives in the selection bar's overflow menu.
Future<void> _selectAll(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select all'));
}

ActiveSessionView _sessionWith(FakeSftpTree tree) =>
    _sessionOn(FakeSftpSshService(FakeSftpClient(tree)));

ActiveSessionView _sessionOn(FakeSftpSshService service) => ActiveSessionView(
  id: 'session-1',
  profile: profileFixture(),
  connectedAt: DateTime.now(),
  sshService: service,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sftpShowHiddenSetting.load();
  });

  testWidgets('lists directory contents on load', (tester) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpDir('projects'), sftpFile('report.pdf', size: 2048)],
    });
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    expect(find.text('projects'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
  });

  testWidgets('the refresh button lists the folder again', (tester) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpFile('report.pdf', size: 2048)],
    });
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();
    expect(find.text('build.log'), findsNothing);

    tree.children['/home/user']!.add(sftpFile('build.log', size: 10));
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('build.log'), findsOneWidget);
  });

  testWidgets('shows an error state when the initial listing fails', (
    tester,
  ) async {
    final tree = FakeSftpTree({});
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('projects'), findsNothing);
  });

  testWidgets('navigates into a directory and back up via breadcrumbs', (
    tester,
  ) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpDir('projects')],
      '/home/user/projects': [sftpFile('main.dart')],
    });
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('projects'));
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('user'), findsOneWidget);
    expect(find.text('projects'), findsOneWidget);

    await tester.tap(find.text('user'));
    await tester.pumpAndSettle();

    expect(find.text('projects'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);
  });

  group('following the terminal', () {
    final tree = FakeSftpTree({
      '/home/user': [sftpDir('projects'), sftpFile('home.txt')],
      '/home/user/projects': [sftpFile('main.dart')],
      '/srv': [sftpFile('site.conf')],
    });

    Future<GlobalKey<SftpBrowserViewState>> pump(
      WidgetTester tester,
      String? Function() terminal,
    ) async {
      final key = GlobalKey<SftpBrowserViewState>();
      await pumpTestApp(
        tester,
        Scaffold(
          body: SftpBrowserView(
            key: key,
            session: _sessionWith(tree),
            terminalDirectory: () async => terminal(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return key;
    }

    testWidgets('opens where the terminal is, with nothing to go back to', (
      tester,
    ) async {
      final key = await pump(tester, () => '/home/user/projects');

      expect(find.text('main.dart'), findsOneWidget);
      expect(key.currentState!.canGoBackHistory, isFalse);
    });

    testWidgets('opens at home when the terminal\'s folder cannot be listed', (
      tester,
    ) async {
      final key = await pump(tester, () => '/gone');

      expect(find.text('home.txt'), findsOneWidget);
      expect(key.currentState!.canGoBackHistory, isFalse);
    });

    testWidgets('moves only once the terminal has moved', (tester) async {
      var terminal = '/home/user/projects';
      final key = await pump(tester, () => terminal);

      await tester.tap(find.text('user'));
      await tester.pumpAndSettle();
      await key.currentState!.followTerminal();
      await tester.pumpAndSettle();
      expect(find.text('home.txt'), findsOneWidget);

      terminal = '/srv';
      await key.currentState!.followTerminal();
      await tester.pumpAndSettle();
      expect(find.text('site.conf'), findsOneWidget);
    });
  });

  testWidgets('a slower navigation does not overwrite a faster, newer one', (
    tester,
  ) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpDir('a')],
      '/home/user/a': [sftpFile('old-in-a.txt')],
      '/srv': [sftpFile('new-in-b.txt')],
    });
    final sftp = FakeSftpClient(tree);
    var terminal = '/home/user';
    final key = GlobalKey<SftpBrowserViewState>();
    await pumpTestApp(
      tester,
      Scaffold(
        body: SftpBrowserView(
          key: key,
          session: _sessionOn(FakeSftpSshService(sftp)),
          terminalDirectory: () async => terminal,
        ),
      ),
    );
    await tester.pumpAndSettle();

    sftp.gateListing('/home/user/a');
    await tester.tap(find.text('a'));
    await tester.pump();

    terminal = '/srv';
    await key.currentState!.followTerminal();
    await tester.pumpAndSettle();

    expect(find.text('new-in-b.txt'), findsOneWidget);
    expect(find.text('srv'), findsOneWidget);

    sftp.releaseListing('/home/user/a');
    await tester.pumpAndSettle();

    expect(find.text('new-in-b.txt'), findsOneWidget);
    expect(find.text('old-in-a.txt'), findsNothing);
    expect(find.text('srv'), findsOneWidget);
  });

  testWidgets('hides dotfiles until the show-hidden toggle is tapped', (
    tester,
  ) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpFile('visible.txt'), sftpFile('.hidden')],
    });
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    expect(find.text('visible.txt'), findsOneWidget);
    expect(find.text('.hidden'), findsNothing);

    await tester.tap(find.byIcon(PhosphorIconsFill.eyeSlash));
    await tester.pumpAndSettle();

    expect(find.text('.hidden'), findsOneWidget);
  });

  testWidgets('the add menu sits in the path bar, not over the list', (
    tester,
  ) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpFile('a.txt')],
    });
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    final plus = find.byIcon(PhosphorIconsRegular.plus);
    expect(plus, findsOneWidget);
    expect(
      tester.getCenter(plus).dy,
      lessThan(
        tester.getCenter(find.byIcon(PhosphorIconsFill.eyeSlash)).dy + 1,
      ),
    );
    expect(
      tester.getCenter(plus).dy,
      lessThan(tester.getCenter(find.text('a.txt')).dy),
    );
  });

  testWidgets(
    'long-press enters selection mode and select-all selects every row',
    (tester) async {
      final tree = FakeSftpTree({
        '/home/user': [sftpFile('a.txt'), sftpFile('b.txt')],
      });
      await pumpTestApp(
        tester,
        Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('a.txt'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);

      await _selectAll(tester);
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
    },
  );

  testWidgets('select-all again with everything selected clears it', (
    tester,
  ) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpFile('a.txt'), sftpFile('b.txt')],
    });
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('a.txt'));
    await tester.pumpAndSettle();
    await _selectAll(tester);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await _selectAll(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('deleting the selection removes the items from the listing', (
    tester,
  ) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpFile('a.txt'), sftpFile('b.txt')],
    });
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('a.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(PhosphorIconsFill.trash));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('a.txt'), findsNothing);
    expect(find.text('b.txt'), findsOneWidget);
  });

  testWidgets('creating a new folder adds it to the listing', (tester) async {
    final tree = FakeSftpTree({'/home/user': []});
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(PhosphorIconsRegular.plus));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'notes');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('notes'), findsOneWidget);
  });

  testWidgets('renaming an item updates the listing', (tester) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpFile('old.txt')],
    });
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(PhosphorIconsRegular.dotsThreeVertical));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    await tester.enterText(field, 'new.txt');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();

    expect(find.text('new.txt'), findsOneWidget);
    expect(find.text('old.txt'), findsNothing);
  });

  testWidgets('renaming onto an existing name asks before replacing it', (
    tester,
  ) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpFile('old.txt'), sftpFile('taken.txt')],
    });
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(PhosphorIconsRegular.dotsThreeVertical).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'taken.txt');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();

    expect(find.text('Replace file?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('old.txt'), findsOneWidget);
    expect(find.text('taken.txt'), findsOneWidget);
  });

  testWidgets('confirming the replace goes through with the rename', (
    tester,
  ) async {
    final tree = FakeSftpTree({
      '/home/user': [sftpFile('old.txt'), sftpFile('taken.txt')],
    });
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _sessionWith(tree))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(PhosphorIconsRegular.dotsThreeVertical).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'taken.txt');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();

    expect(find.text('old.txt'), findsNothing);
    expect(find.text('taken.txt'), findsOneWidget);
  });
}
