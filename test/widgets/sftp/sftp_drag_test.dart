import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/active_session.dart';
import 'package:termphin/services/settings/sftp_settings.dart';
import 'package:termphin/widgets/sftp/sftp_browser_view.dart';
import 'package:termphin/widgets/sftp/sftp_drag.dart';
import 'package:termphin/widgets/sftp/sftp_file_row.dart';

import '../../support/fixtures.dart';
import '../../support/sftp_fakes.dart';
import '../../support/test_app.dart';

const _desktop = TargetPlatformVariant({TargetPlatform.linux});

typedef _Side = ({FakeSftpTree tree, FakeSftpSshService ssh});

/// A machine whose account may run commands, as a server-side copy needs.
_Side _side(Map<String, List<dynamic>> listing, Map<String, String> contents) {
  final tree = FakeSftpTree({
    for (final entry in listing.entries) entry.key: [...entry.value.cast()],
  }, contents: contents);
  final ssh = FakeSftpSshService(FakeSftpClient(tree));
  ssh.fakeClient.onCommand = (command) => (
    exitCode: 0,
    stdout: command.contains('termphin-exec-ok') ? 'termphin-exec-ok\n' : '',
    stderr: '',
  );
  return (tree: tree, ssh: ssh);
}

ActiveSessionView _session(String id, String profileId, _Side side) =>
    ActiveSessionView(
      id: id,
      profile: profileFixture(id: profileId),
      connectedAt: DateTime.now(),
      sshService: side.ssh,
    );

/// Two file lists side by side, the way a split shows two sessions' files.
Future<void> _pumpTwo(
  WidgetTester tester, {
  required _Side left,
  required _Side right,
  required bool sameMachine,
}) async {
  await pumpTestApp(
    tester,
    Scaffold(
      body: Row(
        children: [
          Expanded(
            child: SftpBrowserView(
              key: const ValueKey('left'),
              session: _session('left', 'machine-a', left),
            ),
          ),
          Expanded(
            child: SftpBrowserView(
              key: const ValueKey('right'),
              session: _session(
                'right',
                sameMachine ? 'machine-a' : 'machine-b',
                right,
              ),
            ),
          ),
        ],
      ),
    ),
  );
  await _settle(tester);
}

/// The copies between machines touch real files in a temp folder, which only
/// make progress on the real event loop.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Finder _row(String side, String name) => find.descendant(
  of: find.byKey(ValueKey(side)),
  matching: find.ancestor(
    of: find.text(name),
    matching: find.byType(SftpFileRow),
  ),
);

Future<void> _drag(
  WidgetTester tester,
  Finder from,
  Offset to, {
  LogicalKeyboardKey? holding,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(from),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveBy(const Offset(30, 0));
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  if (holding != null) await tester.sendKeyDownEvent(holding);
  await gesture.up();
  if (holding != null) await tester.sendKeyUpEvent(holding);
  await _settle(tester);
}

Offset _emptyPartOf(WidgetTester tester, String side) {
  final rect = tester.getRect(find.byKey(ValueKey(side)));
  return Offset(rect.center.dx, rect.bottom - 30);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sftpShowHiddenSetting.load();
    await sftpSortFieldSetting.load();
    await sftpSortDescendingSetting.load();
  });

  group('sftpDropAction', () {
    test('between machines is always a copy through the app', () {
      for (final shift in [false, true]) {
        expect(
          sftpDropAction(
            sameMachine: false,
            sameList: false,
            shift: shift,
            primary: false,
          ),
          SftpDropAction.copyAcross,
        );
      }
    });

    test('into another list on one machine copies, Shift moves', () {
      expect(
        sftpDropAction(
          sameMachine: true,
          sameList: false,
          shift: false,
          primary: false,
        ),
        SftpDropAction.copy,
      );
      expect(
        sftpDropAction(
          sameMachine: true,
          sameList: false,
          shift: true,
          primary: false,
        ),
        SftpDropAction.move,
      );
    });

    test('onto a folder in the same list moves, Ctrl copies', () {
      expect(
        sftpDropAction(
          sameMachine: true,
          sameList: true,
          shift: false,
          primary: false,
        ),
        SftpDropAction.move,
      );
      expect(
        sftpDropAction(
          sameMachine: true,
          sameList: true,
          shift: false,
          primary: true,
        ),
        SftpDropAction.copy,
      );
    });
  });

  testWidgets('a file dragged to another machine arrives with its content', (
    tester,
  ) async {
    final left = _side(
      {
        '/home/user': [sftpFile('notes.txt', size: 5)],
      },
      {'/home/user/notes.txt': 'hello'},
    );
    final right = _side({'/home/user': []}, {});
    await _pumpTwo(tester, left: left, right: right, sameMachine: false);

    await _drag(
      tester,
      _row('left', 'notes.txt'),
      _emptyPartOf(tester, 'right'),
    );

    expect(right.tree.contents['/home/user/notes.txt'], 'hello');
    expect(left.tree.contents['/home/user/notes.txt'], 'hello');
    expect(_row('right', 'notes.txt'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('a folder dragged to another machine arrives with its subtree', (
    tester,
  ) async {
    final left = _side(
      {
        '/home/user': [sftpDir('project')],
        '/home/user/project': [sftpFile('a.txt'), sftpDir('src')],
        '/home/user/project/src': [sftpFile('main.dart')],
      },
      {
        '/home/user/project/a.txt': 'aaaa',
        '/home/user/project/src/main.dart': 'void main() {}',
      },
    );
    final right = _side({'/home/user': []}, {});
    await _pumpTwo(tester, left: left, right: right, sameMachine: false);

    await _drag(tester, _row('left', 'project'), _emptyPartOf(tester, 'right'));

    expect(right.tree.contents['/home/user/project/a.txt'], 'aaaa');
    expect(
      right.tree.contents['/home/user/project/src/main.dart'],
      'void main() {}',
    );
  }, variant: _desktop);

  testWidgets('a selection of two files travels together', (tester) async {
    final left = _side(
      {
        '/home/user': [sftpFile('one.txt'), sftpFile('two.txt')],
      },
      {'/home/user/one.txt': '1', '/home/user/two.txt': '2'},
    );
    final right = _side({'/home/user': []}, {});
    await _pumpTwo(tester, left: left, right: right, sameMachine: false);

    await tester.tap(_row('left', 'one.txt'), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(_row('left', 'two.txt'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 400));

    await _drag(tester, _row('left', 'two.txt'), _emptyPartOf(tester, 'right'));

    expect(right.tree.contents['/home/user/one.txt'], '1');
    expect(right.tree.contents['/home/user/two.txt'], '2');
  }, variant: _desktop);

  testWidgets('on one machine a drop copies on the server', (tester) async {
    final side = _side(
      {
        '/home/user': [sftpFile('notes.txt'), sftpDir('backup')],
        '/home/user/backup': [],
      },
      {'/home/user/notes.txt': 'n'},
    );
    await _pumpTwo(tester, left: side, right: side, sameMachine: true);
    await tester.dblTapLike('right', 'backup');

    await _drag(
      tester,
      _row('left', 'notes.txt'),
      _emptyPartOf(tester, 'right'),
    );

    final commands = side.ssh.fakeClient.commands.join('\n');
    expect(commands, contains('cp'));
    expect(commands, contains('/home/user/backup/notes.txt'));
  }, variant: _desktop);

  testWidgets('on one machine Shift at the drop moves', (tester) async {
    final side = _side(
      {
        '/home/user': [sftpFile('notes.txt'), sftpDir('backup')],
        '/home/user/backup': [],
      },
      {'/home/user/notes.txt': 'n'},
    );
    await _pumpTwo(tester, left: side, right: side, sameMachine: true);
    await tester.dblTapLike('right', 'backup');

    await _drag(
      tester,
      _row('left', 'notes.txt'),
      _emptyPartOf(tester, 'right'),
      holding: LogicalKeyboardKey.shiftLeft,
    );

    expect(side.tree.contents['/home/user/backup/notes.txt'], 'n');
    expect(side.tree.contents.containsKey('/home/user/notes.txt'), isFalse);
  }, variant: _desktop);

  testWidgets('a file dropped on a folder of its own list moves into it', (
    tester,
  ) async {
    final side = _side(
      {
        '/home/user': [sftpFile('notes.txt'), sftpDir('backup')],
        '/home/user/backup': [],
      },
      {'/home/user/notes.txt': 'n'},
    );
    final other = _side({'/home/user': []}, {});
    await _pumpTwo(tester, left: side, right: other, sameMachine: false);

    await _drag(
      tester,
      _row('left', 'notes.txt'),
      tester.getCenter(_row('left', 'backup')),
    );

    expect(side.tree.contents['/home/user/backup/notes.txt'], 'n');
    expect(_row('left', 'notes.txt'), findsNothing);
  }, variant: _desktop);

  testWidgets('a folder dropped on itself changes nothing', (tester) async {
    final side = _side({
      '/home/user': [sftpDir('backup')],
      '/home/user/backup': [],
    }, {});
    final other = _side({'/home/user': []}, {});
    await _pumpTwo(tester, left: side, right: other, sameMachine: false);

    await _drag(
      tester,
      _row('left', 'backup'),
      tester.getCenter(_row('left', 'backup')) + const Offset(40, 0),
    );

    expect(side.tree.children['/home/user']!.map((e) => e.filename), [
      'backup',
    ]);
    expect(
      side.ssh.fakeClient.commands.where(
        (c) => !c.contains('termphin-exec-ok'),
      ),
      isEmpty,
    );
  }, variant: _desktop);

  testWidgets('a folder dropped from the computer uploads with its files', (
    tester,
  ) async {
    final right = _side({'/home/user': []}, {});
    final local = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('termphin-test-');
      await Directory('${dir.path}/photos/2026').create(recursive: true);
      await File('${dir.path}/photos/2026/a.txt').writeAsString('pic');
      return dir;
    });
    addTearDown(() => local!.delete(recursive: true));
    await pumpTestApp(
      tester,
      Scaffold(body: SftpBrowserView(session: _session('s', 'm', right))),
    );
    await _settle(tester);

    final state = tester.state(find.byType(SftpBrowserView));
    final upload =
        (state as dynamic).debugUploadDropped
            as Future<void> Function(List<String>);
    unawaited(upload(['${local!.path}/photos']));
    await _settle(tester);

    expect(right.tree.contents['/home/user/photos/2026/a.txt'], 'pic');
  }, variant: _desktop);
}

extension on WidgetTester {
  /// Opens [folder] in the list on [side], the way a double click does.
  Future<void> dblTapLike(String side, String folder) async {
    await tap(_row(side, folder), kind: PointerDeviceKind.mouse);
    await pump(const Duration(milliseconds: 80));
    await tap(_row(side, folder), kind: PointerDeviceKind.mouse);
    await _settle(this);
  }
}
