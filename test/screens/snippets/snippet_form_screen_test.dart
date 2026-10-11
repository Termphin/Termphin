import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/snippet.dart';
import 'package:termphin/providers/snippets_provider.dart';
import 'package:termphin/screens/snippets/snippet_form_screen.dart';

import '../../support/rebuild_counter.dart';
import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder defaultField(String name) =>
      find.byKey(ValueKey('snippetDefaultField:$name'));

  testWidgets('no arguments section until the command mentions one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const SnippetFormScreen());
    await tester.pumpAndSettle();

    expect(defaultField('host'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('snippetCommandField')),
      'ssh {{host}}',
    );
    await tester.pumpAndSettle();

    expect(defaultField('host'), findsOneWidget);
  });

  testWidgets('a field appears per placeholder, in the order written', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const SnippetFormScreen());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('snippetCommandField')),
      'ssh {{host}} -p {{port}}',
    );
    await tester.pumpAndSettle();

    expect(defaultField('host'), findsOneWidget);
    expect(defaultField('port'), findsOneWidget);
    expect(
      tester.getTopLeft(defaultField('host')).dy,
      lessThan(tester.getTopLeft(defaultField('port')).dy),
    );
  });

  testWidgets('typed defaults are saved with the snippet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpTestApp(tester, const SnippetFormScreen(), container: container);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('snippetNameField')),
      'Connect',
    );
    await tester.enterText(
      find.byKey(const ValueKey('snippetCommandField')),
      'ssh {{host}} -p {{port}}',
    );
    await tester.pumpAndSettle();

    await tester.enterText(defaultField('host'), 'example.com');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = container.read(snippetsProvider).single;
    expect(saved.defaults, {'host': 'example.com'});
    expect(saved.defaultFor('port'), '');
  });

  testWidgets('editing shows the defaults already saved', (tester) async {
    final snippet = Snippet(
      id: 'connect',
      name: 'Connect',
      command: 'ssh {{host}}',
      createdAt: DateTime(2026, 7, 30),
      defaults: const {'host': 'example.com'},
    );
    SharedPreferences.setMockInitialValues({
      'snippets': Snippet.encodeList([snippet]),
    });

    await pumpTestApp(tester, SnippetFormScreen(existing: snippet));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: defaultField('host'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'example.com',
    );
  });

  testWidgets('a default survives its placeholder being retyped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const SnippetFormScreen());
    await tester.pumpAndSettle();

    final command = find.byKey(const ValueKey('snippetCommandField'));
    await tester.enterText(command, 'ssh {{host}}');
    await tester.pumpAndSettle();
    await tester.enterText(defaultField('host'), 'example.com');
    await tester.pumpAndSettle();

    await tester.enterText(command, 'ssh {{host');
    await tester.pumpAndSettle();
    expect(defaultField('host'), findsNothing);

    await tester.enterText(command, 'ssh {{host}}');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: defaultField('host'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'example.com',
    );
  });

  testWidgets('a keystroke rebuilds the save button, not the whole form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const SnippetFormScreen());
    await tester.pumpAndSettle();

    final command = find.byKey(const ValueKey('snippetCommandField'));
    await tester.enterText(command, 'echo hello world');
    await tester.pumpAndSettle();

    final rebuilds = await recordRebuilds(tester, () async {
      await tester.enterText(command, 'echo hello worldX');
      await tester.pump();
    });

    expect(rebuilds, hasLength(lessThan(120)));
    expect(rebuilt(rebuilds, 'AppTagsField'), isFalse);
  });
}
