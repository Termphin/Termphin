import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/completion/command_completion.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/terminal/command_suggestion_popup.dart';

const _best = CommandSuggestion(
  label: 'docker run --rm -it ubuntu',
  insert: ' --rm -it ubuntu',
  kind: SuggestionKind.history,
);
const _second = CommandSuggestion(
  label: 'docker run -d nginx',
  insert: ' -d nginx',
  kind: SuggestionKind.history,
);
const _third = CommandSuggestion(
  label: 'docker ps',
  insert: 'ps ',
  kind: SuggestionKind.word,
);
const _fourth = CommandSuggestion(
  label: 'docker pull',
  insert: 'pull ',
  kind: SuggestionKind.word,
);

void main() {
  CommandSuggestion? accepted;
  var dismissed = 0;

  Future<void> pump(
    WidgetTester tester, {
    required double cursorTop,
    double cursorLeft = 100,
    List<CommandSuggestion> suggestions = const [_best, _second, _third],
  }) {
    accepted = null;
    dismissed = 0;
    return tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Stack(
              children: [
                CommandSuggestionPopup(
                  cursor: Rect.fromLTWH(cursorLeft, cursorTop, 8, 16),
                  suggestions: suggestions,
                  onAccept: (s) => accepted = s,
                  onDismiss: () => dismissed++,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Finder row(CommandSuggestion s) =>
      find.byKey(ValueKey('commandSuggestion-${s.label}'));

  Rect card(WidgetTester tester) => tester.getRect(find.byType(Material).last);

  testWidgets('floats above the cursor row, the best one nearest to it', (
    tester,
  ) async {
    await pump(tester, cursorTop: 400);

    expect(card(tester).bottom, lessThanOrEqualTo(400));
    final best = tester.getRect(row(_best));
    expect(best.top, greaterThan(tester.getRect(row(_second)).top));
    expect(best.top, greaterThan(tester.getRect(row(_third)).top));
  });

  testWidgets('below the cursor at the top of the screen, best on top', (
    tester,
  ) async {
    await pump(tester, cursorTop: 10);

    expect(card(tester).top, greaterThanOrEqualTo(26));
    expect(
      tester.getRect(row(_best)).top,
      lessThan(tester.getRect(row(_second)).top),
    );
  });

  testWidgets('shows at most three', (tester) async {
    await pump(
      tester,
      cursorTop: 400,
      suggestions: const [_best, _second, _third, _fourth],
    );

    expect(row(_third), findsOneWidget);
    expect(row(_fourth), findsNothing);
  });

  testWidgets('shows fewer when there is no room for three', (tester) async {
    await pump(tester, cursorTop: 130);

    expect(row(_best), findsOneWidget);
    expect(row(_third), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the whole command, typed part included', (tester) async {
    await pump(tester, cursorTop: 400);

    expect(
      find.text('docker run --rm -it ubuntu', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a tap on a row takes that one', (tester) async {
    await pump(tester, cursorTop: 400);

    await tester.tap(row(_second));

    expect(accepted, _second);
    expect(dismissed, 0);
  });

  testWidgets('X closes it without taking anything', (tester) async {
    await pump(tester, cursorTop: 400);

    await tester.tap(find.byKey(const ValueKey('commandSuggestionDismiss')));

    expect(dismissed, 1);
    expect(accepted, isNull);
  });

  testWidgets('starts at the cursor, not at the edge of the screen', (
    tester,
  ) async {
    await pump(tester, cursorTop: 400, cursorLeft: 200);

    expect(card(tester).left, closeTo(200 - 28, 1));
  });

  testWidgets('moves left only as far as it must to stay on screen', (
    tester,
  ) async {
    await pump(tester, cursorTop: 400, cursorLeft: 780);
    final screen = tester.getSize(find.byType(Scaffold));

    expect(card(tester).right, lessThanOrEqualTo(screen.width - 8));
    expect(card(tester).left, greaterThanOrEqualTo(8));
  });
}
