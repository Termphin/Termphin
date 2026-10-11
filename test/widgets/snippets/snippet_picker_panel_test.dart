import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/snippet.dart';
import 'package:termphin/widgets/snippets/snippet_picker_panel.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t = AppLocale.en.buildSync();

  Future<void> openPicker(
    WidgetTester tester, {
    required void Function(Snippet, Map<String, String>) onSelect,
  }) async {
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showSnippetSpotlight(context, onSelect: onSelect),
            child: const Text('Open snippets'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open snippets'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens straight into the snippet list, with its own title', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await openPicker(tester, onSelect: (_, _) {});

    expect(find.byType(SnippetPickerPanel), findsOneWidget);
    expect(find.text(t.commandPalette.insertSnippetTitle), findsOneWidget);
  });

  testWidgets('the close button dismisses the picker', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await openPicker(tester, onSelect: (_, _) {});
    await tester.tap(find.byTooltip(t.common.close));
    await tester.pumpAndSettle();

    expect(find.byType(SnippetPickerPanel), findsNothing);
  });

  testWidgets('focuses search, resizes for results, and selects with Enter', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 30);
    final snippets = [
      Snippet(
        id: 'deploy',
        name: 'Deploy production',
        command: './deploy.sh',
        createdAt: now,
      ),
      for (var index = 1; index < 5; index++)
        Snippet(
          id: 'snippet-$index',
          name: 'Command $index',
          command: 'command-$index',
          createdAt: now.subtract(Duration(minutes: index)),
        ),
    ];
    SharedPreferences.setMockInitialValues({
      'snippets': Snippet.encodeList(snippets),
    });
    Snippet? selected;

    await openPicker(tester, onSelect: (snippet, _) => selected = snippet);

    final search = find.byKey(const ValueKey('snippetSearchField'));
    final editable = tester.widget<EditableText>(
      find.descendant(of: search, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);

    final card = find
        .descendant(
          of: find.byType(SnippetPickerPanel),
          matching: find.byType(AnimatedContainer),
        )
        .first;
    final initialHeight = tester.getSize(card).height;

    await tester.enterText(search, 'Deploy production');
    await tester.pumpAndSettle();

    expect(tester.getSize(card).height, lessThan(initialHeight));

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(selected?.id, 'deploy');
    expect(find.byType(SnippetPickerPanel), findsNothing);
  });

  testWidgets('arrows move the Enter row, and Enter runs it', (tester) async {
    final now = DateTime(2026, 7, 30);
    SharedPreferences.setMockInitialValues({
      'snippets': Snippet.encodeList([
        for (var index = 0; index < 3; index++)
          Snippet(
            id: 'snippet-$index',
            name: 'Command $index',
            command: 'command-$index',
            createdAt: now.subtract(Duration(minutes: index)),
          ),
      ]),
    });
    Snippet? selected;

    await openPicker(tester, onSelect: (snippet, _) => selected = snippet);
    Finder hintOn(String name) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(Row)).first,
      matching: find.text(t.commandPalette.enterToRun),
    );
    final names = [
      for (final e in find.textContaining('Command ').evaluate())
        (e.widget as Text).data!,
    ];
    expect(hintOn(names[0]), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(hintOn(names[2]), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(hintOn(names[0]), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(hintOn(names[0]), findsNothing);
    expect(hintOn(names[2]), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(selected?.name, names[1]);
  });

  testWidgets('argument fields start on the snippet\'s saved defaults', (
    tester,
  ) async {
    final snippet = Snippet(
      id: 'connect',
      name: 'Connect',
      command: 'ssh {{host}} -p {{port}}',
      createdAt: DateTime(2026, 7, 30),
      defaults: const {'host': 'example.com'},
    );
    SharedPreferences.setMockInitialValues({
      'snippets': Snippet.encodeList([snippet]),
    });
    Map<String, String>? selectedValues;

    await openPicker(tester, onSelect: (_, values) => selectedValues = values);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    String textOf(String name) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(ValueKey('snippetArgField:$name')),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;

    expect(textOf('host'), 'example.com');
    expect(textOf('port'), '');

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.enterText(
      find.byKey(const ValueKey('snippetArgField:port')),
      '2222',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(selectedValues, {'host': 'example.com', 'port': '2222'});
  });

  testWidgets('moves through snippet arguments and confirms with Enter', (
    tester,
  ) async {
    final snippet = Snippet(
      id: 'connect',
      name: 'Connect',
      command: 'ssh {{host}} -p {{port}}',
      createdAt: DateTime(2026, 7, 30),
    );
    SharedPreferences.setMockInitialValues({
      'snippets': Snippet.encodeList([snippet]),
    });
    Snippet? selected;
    Map<String, String>? selectedValues;

    await openPicker(
      tester,
      onSelect: (snippet, values) {
        selected = snippet;
        selectedValues = values;
      },
    );

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    final hostField = find.byKey(const ValueKey('snippetArgField:host'));
    final portField = find.byKey(const ValueKey('snippetArgField:port'));
    expect(tester.getSize(hostField).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(portField).height, greaterThanOrEqualTo(48));
    final hostEditable = tester.widget<EditableText>(
      find.descendant(of: hostField, matching: find.byType(EditableText)),
    );
    expect(hostEditable.focusNode.hasFocus, isTrue);

    await tester.enterText(hostField, 'server.example.com');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    final portEditable = tester.widget<EditableText>(
      find.descendant(of: portField, matching: find.byType(EditableText)),
    );
    expect(portEditable.focusNode.hasFocus, isTrue);

    await tester.enterText(portField, '2222');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(selected?.id, 'connect');
    expect(selectedValues, {'host': 'server.example.com', 'port': '2222'});
    expect(find.byType(SnippetPickerPanel), findsNothing);
  });

  testWidgets('cancelling the arguments goes back to the list', (tester) async {
    final snippet = Snippet(
      id: 'connect',
      name: 'Connect',
      command: 'ssh {{host}}',
      createdAt: DateTime(2026, 7, 30),
    );
    SharedPreferences.setMockInitialValues({
      'snippets': Snippet.encodeList([snippet]),
    });
    Snippet? selected;

    await openPicker(tester, onSelect: (snippet, _) => selected = snippet);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snippetArgField:host')), findsOneWidget);

    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.byKey(const ValueKey('snippetArgField:host')), findsNothing);
    expect(find.byType(SnippetPickerPanel), findsOneWidget);
  });
}
