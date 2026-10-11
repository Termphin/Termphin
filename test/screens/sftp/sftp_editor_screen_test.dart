import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart' as re;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/active_session.dart';
import 'package:termphin/screens/sftp/sftp_editor_screen.dart';
import 'package:termphin/services/settings/editor_settings.dart';
import 'package:termphin/services/sftp/sftp_service.dart';

import '../../support/fixtures.dart';
import '../../support/platform_mocks.dart';
import '../../support/rebuild_counter.dart';
import '../../support/sftp_fakes.dart';
import '../../support/test_app.dart';

const _dir = '/home/user';
const _path = '$_dir/notes.txt';

/// The editor used to rebuild on every keystroke because the chrome that
/// actually depends on the text - one enabled/disabled Save button - worked
/// out whether to rebuild by reading `controller.text`, a copy of the whole
/// file, several times per build. The editor repainting itself is its own
/// business; the screen around it must not rebuild with it.
void main() {
  final t = AppLocale.en.buildSync();

  late FakeSftpTree tree;
  late FakeSftpClient client;
  late SftpService sftp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await editorSettings.load();
  });

  /// The load decodes and splits on an isolate (`compute`), which only makes
  /// progress on the real event loop - under the fake clock alone the editor
  /// never appears and `pumpAndSettle` spins on the progress indicator.
  Future<void> settleLoad(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();
  }

  /// Seeds a file and opens the editor on it.
  Future<void> open(
    WidgetTester tester, {
    String content = 'hello\nworld\n',
    int? modifyTime = 1000,
    int lines = 0,
  }) async {
    final text = lines > 0
        ? List.generate(lines, (i) => 'line $i').join('\n')
        : content;
    tree = FakeSftpTree(
      {
        _dir: [
          sftpFile('notes.txt', size: text.length, modifyTime: modifyTime),
        ],
      },
      contents: {_path: text},
    );
    client = FakeSftpClient(tree);
    sftp = SftpService(FakeSftpSshClient(client));
    await sftp.init();

    await pumpTestApp(
      tester,
      SftpEditorScreen(
        session: ActiveSessionView(
          id: 'session-1',
          profile: profileFixture(),
          connectedAt: DateTime.now(),
        ),
        fileItem: sftpFile('notes.txt', size: text.length),
        path: _path,
        sftp: sftp,
      ),
    );
    await settleLoad(tester);
  }

  String editorText(WidgetTester tester) =>
      tester.widget<re.CodeEditor>(find.byType(re.CodeEditor)).controller!.text;

  void type(WidgetTester tester, String text) {
    tester.widget<re.CodeEditor>(find.byType(re.CodeEditor)).controller!.text =
        text;
  }

  IconButton saveButton(WidgetTester tester) => tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip(t.common.save),
      matching: find.byType(IconButton),
    ),
  );

  /// Plain pumps rather than `pumpAndSettle`: while the save is in flight the
  /// button is a spinner, and a conflict dialog holds it there for as long as
  /// the question is unanswered - nothing settles until it is.
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byTooltip(t.common.save));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// The system back gesture. There is no back button to tap - the editor is
  /// pumped as the root route - and it is the same path either way: both go
  /// through the screen's PopScope.
  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  group('opening a file', () {
    testWidgets('shows what is on the server', (tester) async {
      await open(tester, content: 'alpha\nbeta');
      expect(editorText(tester), 'alpha\nbeta');
    });

    testWidgets('refuses a file too large to edit rather than loading it', (
      tester,
    ) async {
      tree = FakeSftpTree({
        _dir: [sftpFile('notes.txt', size: 200 * 1024 * 1024)],
      });
      client = FakeSftpClient(tree);
      sftp = SftpService(FakeSftpSshClient(client));
      await sftp.init();

      await pumpTestApp(
        tester,
        SftpEditorScreen(
          session: ActiveSessionView(
            id: 'session-1',
            profile: profileFixture(),
            connectedAt: DateTime.now(),
          ),
          fileItem: sftpFile('notes.txt', size: 200 * 1024 * 1024),
          path: _path,
          sftp: sftp,
        ),
      );
      await settleLoad(tester);

      expect(find.byType(re.CodeEditor), findsNothing);
      expect(
        find.textContaining('too large', findRichText: true),
        findsWidgets,
      );
    });
  });

  group('saving', () {
    testWidgets('writes the edited text back to the server', (tester) async {
      await open(tester, content: 'before');
      type(tester, 'after');
      await tester.pumpAndSettle();

      await tapSave(tester);
      expect(tree.contents[_path], 'after');
      expect(find.text(t.editor.savedSuccess), findsOneWidget);
    });

    testWidgets('is not offered while nothing has been changed', (
      tester,
    ) async {
      await open(tester, content: 'unchanged');
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('leaves no temp file behind', (tester) async {
      await open(tester, content: 'before');
      type(tester, 'after');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(tree.contents.keys.where((k) => k.contains('.tmp')), isEmpty);
      expect(
        tree.children[_dir]!.where((e) => e.filename.contains('.tmp')),
        isEmpty,
      );
    });
  });

  group('a file that changed on the server while it was open', () {
    /// Simulates someone else writing to the file in the meantime. The
    /// editor re-stats after its own save, so that write must not read as a
    /// conflict on the next one; a server that reports no modify time at all
    /// gives it nothing to compare against, so it is not treated as one
    /// either. Refusing the overwrite is a data-loss guard: a save that was
    /// cancelled must not have written.
    Future<void> editAndTouch(WidgetTester tester) async {
      await open(tester, content: 'mine', modifyTime: 1000);
      type(tester, 'my edit');
      await tester.pumpAndSettle();
      tree.children[_dir] = [sftpFile('notes.txt', size: 6, modifyTime: 2000)];
      tree.contents[_path] = 'theirs';
    }

    testWidgets('asks before overwriting', (tester) async {
      await editAndTouch(tester);
      await tapSave(tester);

      expect(find.text(t.editor.modifiedRemotelyTitle), findsOneWidget);
      expect(find.text(t.editor.modifiedRemotelyBody), findsOneWidget);
    });

    testWidgets('cancelling keeps their version, not mine', (tester) async {
      await editAndTouch(tester);
      await tapSave(tester);

      await tester.tap(find.text(t.common.cancel));
      await tester.pumpAndSettle();

      expect(tree.contents[_path], 'theirs');
      expect(find.text(t.editor.savedSuccess), findsNothing);
    });

    testWidgets('save anyway overwrites, as it says', (tester) async {
      await editAndTouch(tester);
      await tapSave(tester);

      await tester.tap(find.text(t.editor.saveAnyway));
      await tester.pumpAndSettle();

      expect(tree.contents[_path], 'my edit');
      expect(find.text(t.editor.savedSuccess), findsOneWidget);
    });

    testWidgets('does not ask again for the version it just wrote', (
      tester,
    ) async {
      await open(tester, content: 'one');
      type(tester, 'two');
      await tester.pumpAndSettle();
      client.nextMtime = 5000;
      await tapSave(tester);
      expect(find.text(t.editor.modifiedRemotelyTitle), findsNothing);

      type(tester, 'three');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(find.text(t.editor.modifiedRemotelyTitle), findsNothing);
      expect(tree.contents[_path], 'three');
    });

    testWidgets('does not ask when the server reports no modify time', (
      tester,
    ) async {
      await open(tester, content: 'one', modifyTime: null);
      type(tester, 'two');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(find.text(t.editor.modifiedRemotelyTitle), findsNothing);
      expect(tree.contents[_path], 'two');
    });
  });

  group('leaving with unsaved changes', () {
    testWidgets('asks before discarding them', (tester) async {
      await open(tester, content: 'before');
      type(tester, 'after');
      await tester.pumpAndSettle();

      await pressBack(tester);

      expect(find.text(t.editor.unsavedTitle), findsOneWidget);
      expect(find.text(t.editor.discardConfirm), findsOneWidget);
    });

    testWidgets('cancelling stays on the file with the edit intact', (
      tester,
    ) async {
      await open(tester, content: 'before');
      type(tester, 'after');
      await tester.pumpAndSettle();

      await pressBack(tester);
      await tester.tap(find.text(t.common.cancel));
      await tester.pumpAndSettle();

      expect(find.byType(re.CodeEditor), findsOneWidget);
      expect(editorText(tester), 'after');
    });

    testWidgets('leaves straight away when nothing was changed', (
      tester,
    ) async {
      await open(tester, content: 'untouched');
      await pressBack(tester);
      expect(find.text(t.editor.unsavedTitle), findsNothing);
    });
  });

  group('a file too long to show at once', () {
    testWidgets('opens the first window and says how much there is', (
      tester,
    ) async {
      await open(tester, lines: 2500);

      expect(editorText(tester).split('\n'), hasLength(1000));
      expect(
        find.textContaining('2500', findRichText: true),
        findsWidgets,
        reason: 'the total belongs on screen, not just the window',
      );
    });

    testWidgets('saves the whole file, not just the window on screen', (
      tester,
    ) async {
      await open(tester, lines: 2500);
      final edited = editorText(tester).replaceFirst('line 0', 'CHANGED');
      type(tester, edited);
      await tester.pumpAndSettle();

      await tapSave(tester);

      final saved = tree.contents[_path]!.split('\n');
      expect(saved, hasLength(2500));
      expect(saved.first, 'CHANGED');
      expect(saved.last, 'line 2499');
    });
  });

  group('editing does not repaint the screen', () {
    testWidgets('once the file is already modified', (tester) async {
      await open(tester, content: 'before');
      type(tester, 'after');
      await tester.pumpAndSettle();

      final rebuilds = await recordRebuilds(tester, () async {
        type(tester, 'after more');
        await tester.pump();
      });

      await tester.pumpAndSettle();

      expect(rebuilt(rebuilds, 'CodeEditor'), isFalse);
      expect(rebuilt(rebuilds, 'Scaffold'), isFalse);
    });

    testWidgets('when only the caret moved', (tester) async {
      await open(tester, content: 'alpha\nbeta');
      final controller = tester
          .widget<re.CodeEditor>(find.byType(re.CodeEditor))
          .controller!;

      final rebuilds = await recordRebuilds(tester, () async {
        controller.selection = const re.CodeLineSelection.collapsed(
          index: 1,
          offset: 2,
        );
        await tester.pump();
      });
      await tester.pumpAndSettle();

      expect(rebuilt(rebuilds, 'CodeEditor'), isFalse);
      expect(rebuilt(rebuilds, 'Scaffold'), isFalse);
    });

    testWidgets('but the first edit does enable Save', (tester) async {
      await open(tester, content: 'before');
      type(tester, 'after');
      await tester.pumpAndSettle();

      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('and saving disables it again', (tester) async {
      await open(tester, content: 'before');
      type(tester, 'after');
      await tester.pumpAndSettle();

      await tapSave(tester);

      expect(saveButton(tester).onPressed, isNull);
    });
  });

  group('display settings', () {
    double fontSize(WidgetTester tester) => tester
        .widget<re.CodeEditor>(find.byType(re.CodeEditor))
        .style!
        .fontSize!;

    testWidgets('line numbers follow the setting', (tester) async {
      await open(tester);
      expect(find.byType(re.DefaultCodeLineNumber), findsWidgets);

      await editorSettings.lineNumbers.set(false);
      await tester.pumpAndSettle();

      expect(find.byType(re.DefaultCodeLineNumber), findsNothing);
    });

    testWidgets('a pinch changes the size and keeps it', (tester) async {
      await open(tester);
      expect(fontSize(tester), 13);

      final centre = tester.getCenter(find.byType(re.CodeEditor));
      final a = await tester.startGesture(centre - const Offset(40, 0));
      final b = await tester.startGesture(
        centre + const Offset(40, 0),
        pointer: 2,
      );
      await b.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(fontSize(tester), 19.5);

      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(editorSettings.fontSize.value, 19.5);
    });

    testWidgets('line height and tab width come from the settings', (
      tester,
    ) async {
      await editorSettings.lineHeight.set(1.8);
      await editorSettings.tabWidth.set(4);
      await open(tester);

      final editor = tester.widget<re.CodeEditor>(find.byType(re.CodeEditor));
      expect(editor.style!.fontHeight, 1.8);
      expect(editor.controller!.options.indentSize, 4);
    });

    testWidgets('the wrap button is the same setting', (tester) async {
      await open(tester);
      expect(editorSettings.wordWrap.value, isTrue);

      await tester.tap(find.byTooltip(t.editor.toggleWordWrap));
      await tester.pumpAndSettle();

      expect(editorSettings.wordWrap.value, isFalse);
      expect(
        tester.widget<re.CodeEditor>(find.byType(re.CodeEditor)).wordWrap,
        isFalse,
      );
    });
  });

  group('find and replace', () {
    /// Matches are found on re_editor's own isolate, which only runs on the
    /// real event loop.
    Future<void> settleFind(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump();
      }
    }

    Future<void> search(WidgetTester tester, String pattern) async {
      await tester.tap(find.byTooltip(t.editor.find));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, t.editor.findHint),
        pattern,
      );
      await settleFind(tester);
    }

    testWidgets('counts the matches and steps through them', (tester) async {
      await open(tester, content: 'alpha\nbeta\nalpha');
      await search(tester, 'alpha');

      expect(find.text('1/2'), findsOneWidget);
      await tester.tap(find.byTooltip(t.editor.nextMatch));
      await settleFind(tester);
      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('says when there is nothing to find', (tester) async {
      await open(tester, content: 'alpha\nbeta');
      await search(tester, 'zeta');

      expect(find.text(t.editor.noMatches), findsOneWidget);
    });

    testWidgets('replace all rewrites every match', (tester) async {
      await open(tester, content: 'alpha\nbeta\nalpha');
      await search(tester, 'alpha');

      await tester.tap(find.byTooltip(t.editor.replace));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, t.editor.replaceHint),
        'gamma',
      );
      await tester.pump();
      await tester.tap(find.text(t.editor.replaceAll));
      await settleFind(tester);

      expect(editorText(tester), 'gamma\nbeta\ngamma');
    });
  });

  testWidgets('holding a word offers copy and paste, and copy copies it', (
    tester,
  ) async {
    final clipboard = ClipboardMock()..install();
    addTearDown(clipboard.uninstall);
    await open(tester, content: 'hello world');

    await tester.longPressAt(
      tester.getTopLeft(find.byType(re.CodeEditor)) + const Offset(60, 20),
    );
    await tester.pumpAndSettle();

    final labels = MaterialLocalizations.of(
      tester.element(find.byType(re.CodeEditor)),
    );
    expect(find.text(labels.copyButtonLabel), findsOneWidget);
    expect(find.text(labels.pasteButtonLabel), findsOneWidget);

    await tester.tap(find.text(labels.copyButtonLabel));
    await tester.pumpAndSettle();
    expect(clipboard.text, isNotEmpty);
    expect('hello world', contains(clipboard.text!));
    expect(find.text(labels.copyButtonLabel), findsNothing);
  });
}
