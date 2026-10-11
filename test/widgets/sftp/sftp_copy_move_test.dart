import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/active_session.dart';
import 'package:termphin/services/settings/sftp_settings.dart';
import 'package:termphin/services/sftp/sftp_remote_ops.dart';
import 'package:termphin/widgets/sftp/sftp_browser_view.dart';
import 'package:termphin/widgets/sftp/sftp_folder_picker.dart';

import '../../support/fixtures.dart';
import '../../support/sftp_fakes.dart';
import '../../support/test_app.dart';

/// A server that runs commands: the probe finds its marker, the rest succeed.
FakeCommandResult _shell(String command) => command.contains(execProbeMarker)
    ? (exitCode: 0, stdout: execProbeMarker, stderr: '')
    : (exitCode: 0, stdout: '', stderr: '');

Finder _inPicker(Finder finder) =>
    find.descendant(of: find.byType(SftpFolderPicker), matching: finder);

/// One browser over [tree], on a server that runs commands unless told
/// otherwise.
class _Harness {
  _Harness(
    this.tree, {
    FutureOr<FakeCommandResult> Function(String)? onCommand = _shell,
  }) : sftp = FakeSftpClient(tree) {
    service = FakeSftpSshService(sftp);
    service.fakeClient.onCommand = onCommand;
  }

  final FakeSftpTree tree;
  final FakeSftpClient sftp;
  late final FakeSftpSshService service;

  List<String> get commands => service.fakeClient.commands;

  /// The copies and moves run, probes left out.
  List<String> get fileCommands =>
      commands.where((c) => !c.contains(execProbeMarker)).toList();

  List<String> names(String folder) =>
      tree.children[folder]!.map((e) => e.filename).toList();

  Future<void> pump(WidgetTester tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: SftpBrowserView(
          session: ActiveSessionView(
            id: 'session-1',
            profile: profileFixture(),
            connectedAt: DateTime.now(),
            sshService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _openRowMenu(WidgetTester tester, String name) async {
  final row = find.ancestor(of: find.text(name), matching: find.byType(Row));
  await tester.tap(
    find.descendant(
      of: row.first,
      matching: find.byIcon(PhosphorIconsRegular.dotsThreeVertical),
    ),
  );
  await tester.pumpAndSettle();
}

/// Long-presses the first and taps the rest into the selection.
Future<void> _select(WidgetTester tester, List<String> names) async {
  await tester.longPress(find.text(names.first));
  await tester.pumpAndSettle();
  for (final name in names.skip(1)) {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }
}

Future<void> _pick(WidgetTester tester, List<String> folders) async {
  for (final folder in folders) {
    await tester.tap(_inPicker(find.text(folder)));
    await tester.pumpAndSettle();
  }
}

Future<void> _confirm(WidgetTester tester, String action) async {
  await tester.tap(_inPicker(find.widgetWithText(FilledButton, action)));
  await tester.pumpAndSettle();
}

FilledButton _pickerAction(WidgetTester tester, String action) => tester
    .widget<FilledButton>(_inPicker(find.widgetWithText(FilledButton, action)));

/// A toast sits over the top rows until it times out.
Future<void> _waitOutToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sftpShowHiddenSetting.load();
    SftpBrowserViewState.clearRecentDestinations();
  });

  group('moving', () {
    testWidgets('from the row menu into the folder picked', (tester) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpDir('app'), sftpFile('a.txt')],
          '/home/user/app': [],
        }),
      );
      await h.pump(tester);

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Move to…'));
      await tester.pumpAndSettle();
      expect(find.text('Move a.txt to'), findsOneWidget);
      await _pick(tester, ['app']);
      await _confirm(tester, 'Move here');

      expect(h.names('/home/user/app'), ['a.txt']);
      expect(find.text('a.txt'), findsNothing);
      expect(find.text('Moved a.txt'), findsOneWidget);
      expect(h.commands, isEmpty, reason: 'a rename, no command');
    });

    testWidgets('several at once, counted in the title and the toast', (
      tester,
    ) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpDir('app'), sftpFile('a.txt'), sftpFile('b.txt')],
          '/home/user/app': [],
        }),
      );
      await h.pump(tester);

      await _select(tester, ['a.txt', 'b.txt']);
      await tester.tap(find.byTooltip('Move to…'));
      await tester.pumpAndSettle();
      expect(find.text('Move 2 items to'), findsOneWidget);
      await _pick(tester, ['app']);
      await _confirm(tester, 'Move here');

      expect(h.names('/home/user/app'), ['a.txt', 'b.txt']);
      expect(find.text('Moved 2 items'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('across filesystems falls back to mv on the server', (
      tester,
    ) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpDir('app'), sftpFile('a.txt')],
          '/home/user/app': [],
        }),
      );
      h.sftp.renameErrors['/home/user/a.txt'] = SftpStatusError(
        SftpStatusCode.failure,
        'EXDEV',
      );
      await h.pump(tester);

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Move to…'));
      await tester.pumpAndSettle();
      await _pick(tester, ['app']);
      await _confirm(tester, 'Move here');

      expect(h.fileCommands.single, contains('mv --'));
      expect(h.fileCommands.single, contains('/home/user/app/a.txt'));
    });

    testWidgets('a folder cannot go into itself or where it already is', (
      tester,
    ) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpDir('app'), sftpDir('other')],
          '/home/user/app': [sftpDir('src')],
          '/home/user/app/src': [],
          '/home/user/other': [],
        }),
      );
      await h.pump(tester);

      await _select(tester, ['app']);
      await tester.tap(find.byTooltip('Move to…'));
      await tester.pumpAndSettle();
      expect(
        _pickerAction(tester, 'Move here').onPressed,
        isNull,
        reason: 'already in this folder',
      );

      await tester.tap(_inPicker(find.text('app')));
      await tester.pumpAndSettle();
      expect(
        _inPicker(find.text('src')),
        findsNothing,
        reason: 'the folder being moved does not open',
      );

      await _pick(tester, ['other']);
      expect(_pickerAction(tester, 'Move here').onPressed, isNotNull);
    });
  });

  group('copying', () {
    testWidgets('runs cp on the server with the paths picked', (tester) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpDir('app'), sftpFile('a.txt')],
          '/home/user/app': [],
        }),
      );
      await h.pump(tester);

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Copy to…'));
      await tester.pumpAndSettle();
      expect(find.text('Copy a.txt to'), findsOneWidget);
      await _pick(tester, ['app']);
      await _confirm(tester, 'Copy here');

      expect(h.fileCommands.single, contains('cp -RPp'));
      expect(h.fileCommands.single, contains("'/home/user/a.txt'"));
      expect(h.fileCommands.single, contains("'/home/user/app/a.txt'"));
      expect(find.text('Copied a.txt'), findsOneWidget);
    });

    testWidgets('into its own folder makes a second one, no questions', (
      tester,
    ) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpFile('a.txt')],
        }),
      );
      await h.pump(tester);

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Copy to…'));
      await tester.pumpAndSettle();
      await _confirm(tester, 'Copy here');

      expect(find.text('Already there'), findsNothing);
      expect(h.fileCommands.single, contains("'/home/user/a (1).txt'"));
    });

    testWidgets('duplicate picks a name free beside the original', (
      tester,
    ) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpFile('a.txt'), sftpFile('a (1).txt')],
        }),
      );
      await h.pump(tester);

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      expect(h.fileCommands.single, contains("'/home/user/a (2).txt'"));
      expect(find.text('Copied a (2).txt'), findsOneWidget);
    });

    testWidgets('duplicate asks the server for names, not the old listing', (
      tester,
    ) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpFile('a.txt')],
        }),
      );
      await h.pump(tester);
      h.tree.children['/home/user']!.add(sftpFile('a (1).txt'));

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      expect(h.fileCommands.single, contains("'/home/user/a (2).txt'"));
    });

    testWidgets('what the server refused with is shown', (tester) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpFile('a.txt')],
        }),
        onCommand: (c) => c.contains(execProbeMarker)
            ? _shell(c)
            : (
                exitCode: 1,
                stdout: '',
                stderr: "cp: cannot create 'a (1).txt': Disk quota exceeded\n",
              ),
      );
      await h.pump(tester);

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Disk quota exceeded'), findsOneWidget);
    });

    testWidgets('shows it is working, and takes nothing else meanwhile', (
      tester,
    ) async {
      final done = Completer<FakeCommandResult>();
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpFile('a.txt'), sftpFile('b.txt')],
        }),
        onCommand: (c) => c.contains(execProbeMarker) ? _shell(c) : done.future,
      );
      await h.pump(tester);

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Duplicate'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Copying on the server…'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find
              .ancestor(of: find.text('b.txt'), matching: find.byType(Row))
              .first,
          matching: find.byIcon(PhosphorIconsRegular.dotsThreeVertical),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Duplicate'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.fileCommands, hasLength(1), reason: 'the second one waits out');

      done.complete((exitCode: 0, stdout: '', stderr: ''));
      await tester.pumpAndSettle();
      expect(find.text('Copying on the server…'), findsNothing);
    });

    testWidgets('a server locked to SFTP says so and stops offering copy', (
      tester,
    ) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpFile('a.txt')],
        }),
        onCommand: null,
      );
      await h.pump(tester);

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(find.textContaining('only allows file transfers'), findsOneWidget);
      await _waitOutToast(tester);

      await _openRowMenu(tester, 'a.txt');
      expect(find.text('Duplicate'), findsNothing);
      expect(find.text('Copy to…'), findsNothing);
      expect(find.text('Move to…'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await _select(tester, ['a.txt']);
      final copy = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(PhosphorIconsFill.folders),
          matching: find.byType(IconButton),
        ),
      );
      expect(copy.onPressed, isNull);
      expect(h.fileCommands, isEmpty);
    });
  });

  group('when names clash', () {
    _Harness clashing() => _Harness(
      FakeSftpTree(
        {
          '/home/user': [sftpDir('app'), sftpFile('a.txt'), sftpFile('b.txt')],
          '/home/user/app': [sftpFile('a.txt')],
        },
        contents: {'/home/user/a.txt': 'new', '/home/user/app/a.txt': 'old'},
      ),
    );

    Future<void> moveBothIntoApp(WidgetTester tester) async {
      await _select(tester, ['a.txt', 'b.txt']);
      await tester.tap(find.byTooltip('Move to…'));
      await tester.pumpAndSettle();
      await _pick(tester, ['app']);
      await _confirm(tester, 'Move here');
    }

    testWidgets('asks once for the whole lot, naming the clash', (
      tester,
    ) async {
      final h = clashing();
      await h.pump(tester);

      await moveBothIntoApp(tester);

      expect(find.text('Already there'), findsOneWidget);
      expect(
        find.text('a.txt already exists in /home/user/app.'),
        findsOneWidget,
      );
    });

    testWidgets('cancel changes nothing', (tester) async {
      final h = clashing();
      await h.pump(tester);

      await moveBothIntoApp(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(h.names('/home/user'), ['app', 'a.txt', 'b.txt']);
      expect(h.tree.contents['/home/user/app/a.txt'], 'old');
    });

    testWidgets('skip leaves the clash where it was and says so', (
      tester,
    ) async {
      final h = clashing();
      await h.pump(tester);

      await moveBothIntoApp(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(h.names('/home/user/app'), ['a.txt', 'b.txt']);
      expect(h.tree.contents['/home/user/app/a.txt'], 'old');
      expect(h.names('/home/user'), contains('a.txt'));
      expect(h.sftp.removedPaths, isEmpty);
      expect(find.text('Moved b.txt  ·  1 skipped'), findsOneWidget);
    });

    testWidgets('replace puts the new one in place of the old', (tester) async {
      final h = clashing();
      await h.pump(tester);

      await moveBothIntoApp(tester);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(h.sftp.removedPaths, ['/home/user/app/a.txt']);
      expect(h.names('/home/user/app'), ['a.txt', 'b.txt']);
      expect(h.tree.contents['/home/user/app/a.txt'], 'new');
      expect(h.names('/home/user'), ['app']);
    });

    testWidgets('keep both renames only the clash', (tester) async {
      final h = clashing();
      await h.pump(tester);

      await moveBothIntoApp(tester);
      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();

      expect(h.names('/home/user/app'), ['a.txt', 'a (1).txt', 'b.txt']);
      expect(h.tree.contents['/home/user/app/a.txt'], 'old');
      expect(h.tree.contents['/home/user/app/a (1).txt'], 'new');
      expect(h.sftp.removedPaths, isEmpty);
    });

    testWidgets('skipping everything says nothing changed', (tester) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpDir('app'), sftpFile('a.txt')],
          '/home/user/app': [sftpFile('a.txt')],
        }),
      );
      await h.pump(tester);

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Move to…'));
      await tester.pumpAndSettle();
      await _pick(tester, ['app']);
      await _confirm(tester, 'Move here');
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing changed - every item was skipped'),
        findsOneWidget,
      );
    });
  });

  group('when some fail', () {
    _Harness threeFiles() => _Harness(
      FakeSftpTree({
        '/home/user': [
          sftpDir('app'),
          sftpFile('a.txt'),
          sftpFile('b.txt'),
          sftpFile('c.txt'),
        ],
        '/home/user/app': [],
      }),
    );

    Future<void> moveAllIntoApp(WidgetTester tester) async {
      await _select(tester, ['a.txt', 'b.txt', 'c.txt']);
      await tester.tap(find.byTooltip('Move to…'));
      await tester.pumpAndSettle();
      await _pick(tester, ['app']);
      await _confirm(tester, 'Move here');
    }

    testWidgets('one failure is named, and the rest still go', (tester) async {
      final h = threeFiles();
      h.sftp.renameErrors['/home/user/b.txt'] = SftpStatusError(
        SftpStatusCode.permissionDenied,
        'denied',
      );
      await h.pump(tester);

      await moveAllIntoApp(tester);

      expect(h.names('/home/user/app'), ['a.txt', 'c.txt']);
      expect(find.textContaining('b.txt: Permission denied'), findsOneWidget);
    });

    testWidgets('several failures are counted', (tester) async {
      final h = threeFiles();
      for (final name in ['a.txt', 'c.txt']) {
        h.sftp.renameErrors['/home/user/$name'] = SftpStatusError(
          SftpStatusCode.permissionDenied,
          'denied',
        );
      }
      await h.pump(tester);

      await moveAllIntoApp(tester);

      expect(h.names('/home/user/app'), ['b.txt']);
      expect(find.textContaining('Could not move 2 items.'), findsOneWidget);
    });
  });

  group('the folder picker', () {
    _Harness nested() => _Harness(
      FakeSftpTree({
        '/': [sftpDir('home')],
        '/home': [sftpDir('user'), sftpDir('shared')],
        '/home/shared': [],
        '/home/user': [sftpDir('app'), sftpDir('.cache'), sftpFile('a.txt')],
        '/home/user/app': [],
        '/home/user/.cache': [],
      }),
    );

    Future<void> openMove(WidgetTester tester) async {
      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Move to…'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists folders only, hidden ones left out', (tester) async {
      final h = nested();
      await h.pump(tester);

      await openMove(tester);

      expect(_inPicker(find.text('app')), findsOneWidget);
      expect(_inPicker(find.text('.cache')), findsNothing);
      expect(_inPicker(find.text('a.txt')), findsNothing);
    });

    testWidgets('goes up with ..', (tester) async {
      final h = nested();
      await h.pump(tester);

      await openMove(tester);
      await _pick(tester, ['..', 'shared']);
      await _confirm(tester, 'Move here');

      expect(h.names('/home/shared'), ['a.txt']);
    });

    testWidgets('takes a typed path', (tester) async {
      final h = nested();
      await h.pump(tester);

      await openMove(tester);
      await tester.tap(_inPicker(find.byTooltip('Edit path')));
      await tester.pumpAndSettle();
      await tester.enterText(_inPicker(find.byType(TextField)), '/home/shared');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await _confirm(tester, 'Move here');

      expect(h.names('/home/shared'), ['a.txt']);
    });

    testWidgets('makes a new folder and goes into it', (tester) async {
      final h = nested();
      await h.pump(tester);

      await openMove(tester);
      await tester.tap(_inPicker(find.text('New folder')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'archive');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await _confirm(tester, 'Move here');

      expect(h.names('/home/user/archive'), ['a.txt']);
    });

    testWidgets('closed without a pick, nothing happens', (tester) async {
      final h = nested();
      await h.pump(tester);

      await _select(tester, ['a.txt']);
      await tester.tap(find.byTooltip('Move to…'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(SftpFolderPicker), findsNothing);
      expect(find.text('1 selected'), findsOneWidget);
      expect(h.names('/home/user'), contains('a.txt'));
    });

    testWidgets('offers where the last move went', (tester) async {
      final h = _Harness(
        FakeSftpTree({
          '/home/user': [sftpDir('app'), sftpFile('a.txt'), sftpFile('b.txt')],
          '/home/user/app': [],
        }),
      );
      await h.pump(tester);

      await _openRowMenu(tester, 'a.txt');
      await tester.tap(find.text('Move to…'));
      await tester.pumpAndSettle();
      expect(_inPicker(find.text('Recent')), findsNothing);
      await _pick(tester, ['app']);
      await _confirm(tester, 'Move here');
      await _waitOutToast(tester);

      await _openRowMenu(tester, 'b.txt');
      await tester.tap(find.text('Move to…'));
      await tester.pumpAndSettle();
      await tester.tap(
        _inPicker(find.widgetWithText(ActionChip, '/home/user/app')),
      );
      await tester.pumpAndSettle();
      await _confirm(tester, 'Move here');

      expect(h.names('/home/user/app'), ['a.txt', 'b.txt']);
    });
  });
}
