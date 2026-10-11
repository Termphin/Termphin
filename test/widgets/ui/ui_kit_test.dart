import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/ui/app_card.dart';
import 'package:termphin/widgets/ui/app_divider.dart';
import 'package:termphin/widgets/ui/empty_state.dart';
import 'package:termphin/widgets/ui/section_header.dart';
import 'package:termphin/widgets/ui/stepper_row.dart';
import 'package:termphin/widgets/ui/tag_chip.dart';
import 'package:termphin/widgets/ui/two_line_label.dart';

import '../../support/test_app.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await pumpTestApp(tester, Scaffold(body: Center(child: child)));
  await tester.pumpAndSettle();
}

void main() {
  group('StepperRow', () {
    testWidgets('steps by one in each direction', (tester) async {
      final seen = <int>[];
      await _pump(
        tester,
        StepperRow(
          label: 'Columns',
          value: 5,
          min: 1,
          max: 9,
          onChanged: seen.add,
        ),
      );

      expect(find.text('Columns'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      await tester.tap(find.byIcon(PhosphorIconsRegular.plus));
      await tester.tap(find.byIcon(PhosphorIconsRegular.minus));
      expect(seen, [6, 4]);
    });

    testWidgets('refuses to step past either end', (tester) async {
      await _pump(
        tester,
        StepperRow(
          label: 'At the floor',
          value: 1,
          min: 1,
          max: 3,
          onChanged: (_) => fail('should not fire at the minimum'),
        ),
      );
      await tester.tap(find.byIcon(PhosphorIconsRegular.minus));
      await tester.pump();

      await _pump(
        tester,
        StepperRow(
          label: 'At the ceiling',
          value: 3,
          min: 1,
          max: 3,
          onChanged: (_) => fail('should not fire at the maximum'),
        ),
      );
      await tester.tap(find.byIcon(PhosphorIconsRegular.plus));
      await tester.pump();
    });
  });

  group('ValueStepperRow', () {
    Future<List<double>> stepFrom(
      WidgetTester tester,
      double value, {
      double step = 0.1,
      double min = 1.0,
      double max = 2.0,
    }) async {
      final seen = <double>[];
      await _pump(
        tester,
        ValueStepperRow(
          label: 'Line height',
          value: value,
          display: value.toStringAsFixed(2),
          min: min,
          max: max,
          step: step,
          onChanged: seen.add,
        ),
      );
      await tester.tap(find.byIcon(PhosphorIconsRegular.plus));
      await tester.tap(find.byIcon(PhosphorIconsRegular.minus));
      return seen;
    }

    testWidgets('moves by one step each way', (tester) async {
      final seen = await stepFrom(tester, 1.5);
      expect(seen[0], closeTo(1.6, 1e-9));
      expect(seen[1], closeTo(1.4, 1e-9));
    });

    testWidgets('snaps a value that is off the grid back onto it', (
      tester,
    ) async {
      final seen = await stepFrom(tester, 1.47);
      expect(seen[0], closeTo(1.6, 1e-9));
      expect(seen[1], closeTo(1.4, 1e-9));
    });

    testWidgets('never steps outside the range', (tester) async {
      final seen = <double>[];
      await _pump(
        tester,
        ValueStepperRow(
          label: 'Near the top',
          value: 1.95,
          display: '1.95',
          min: 1.0,
          max: 2.0,
          step: 0.1,
          onChanged: seen.add,
        ),
      );
      await tester.tap(find.byIcon(PhosphorIconsRegular.plus));
      expect(seen.single, closeTo(2.0, 1e-9));
    });

    testWidgets('shows the display string, not the raw value', (tester) async {
      await _pump(
        tester,
        ValueStepperRow(
          label: 'Padding',
          value: 6,
          display: '6 px',
          min: 0,
          max: 16,
          step: 1,
          onChanged: (_) {},
        ),
      );
      expect(find.text('6 px'), findsOneWidget);
      expect(find.text('6'), findsNothing);
    });
  });

  group('TagChip', () {
    testWidgets('reports taps and long presses', (tester) async {
      var taps = 0;
      var longPresses = 0;
      await _pump(
        tester,
        TagChip(
          label: 'prod',
          selected: false,
          onTap: () => taps++,
          onLongPress: () => longPresses++,
        ),
      );

      await tester.tap(find.text('prod'));
      await tester.longPress(find.text('prod'));
      expect(taps, 1);
      expect(longPresses, 1);
    });

    testWidgets('the display variant is not interactive', (tester) async {
      await _pump(tester, const TagChip.display(label: 'eu'));
      expect(find.text('eu'), findsOneWidget);
      await tester.tap(find.text('eu'));
      await tester.pumpAndSettle();
    });

    testWidgets('paints the selected one differently', (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            TagChip(label: 'on', selected: true),
            TagChip(label: 'off', selected: false),
          ],
        ),
      );

      BoxDecoration decorationOf(String label) =>
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text(label),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;

      expect(decorationOf('on').color, isNot(decorationOf('off').color));
    });
  });

  group('TwoLineLabel', () {
    testWidgets('reserves two lines whether or not it needs them', (
      tester,
    ) async {
      const style = TextStyle(fontSize: 10, height: 1.3);
      await _pump(
        tester,
        const Column(
          children: [
            TwoLineLabel(text: 'one', style: style),
            TwoLineLabel(
              text: 'a much longer label that wraps onto a second line',
              style: style,
            ),
          ],
        ),
      );

      final heights = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(TwoLineLabel),
              matching: find.byType(SizedBox),
            ),
          )
          .map((box) => box.height)
          .toSet();
      expect(heights, {26.0});
    });

    testWidgets('cuts off rather than growing to a third line', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 60,
          child: TwoLineLabel(
            text: 'one two three four five six seven eight nine ten',
            style: TextStyle(fontSize: 10, height: 1.3),
          ),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('empty states', () {
    testWidgets('the panel shows its title, subtitle and action', (
      tester,
    ) async {
      await _pump(
        tester,
        EmptyStatePanel(
          icon: PhosphorIconsRegular.shieldCheck,
          title: 'Nothing here',
          subtitle: 'It fills up as you go',
          action: TextButton(onPressed: () {}, child: const Text('Do it')),
        ),
      );

      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('It fills up as you go'), findsOneWidget);
      expect(find.text('Do it'), findsOneWidget);
    });

    testWidgets('the panel works with a title alone', (tester) async {
      await _pump(
        tester,
        const EmptyStatePanel(
          icon: PhosphorIconsRegular.shieldCheck,
          title: 'Nothing here',
        ),
      );
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('the hint is one line with an icon', (tester) async {
      await _pump(
        tester,
        const EmptyStateHint(
          icon: PhosphorIconsRegular.arrowsLeftRight,
          text: 'No rules yet',
        ),
      );
      expect(find.text('No rules yet'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.arrowsLeftRight), findsOneWidget);
    });
  });

  group('surfaces', () {
    testWidgets('AppCard wraps what it is given', (tester) async {
      await _pump(tester, const AppCard(child: Text('inside')));
      expect(find.text('inside'), findsOneWidget);
    });

    testWidgets('AppCard.fields stacks its children', (tester) async {
      await _pump(
        tester,
        AppCard.fields(children: const [Text('first'), Text('second')]),
      );
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('the divider is a hairline inset from the left', (
      tester,
    ) async {
      await _pump(tester, const AppDivider(indent: 12));
      final padding = tester.widget<Padding>(
        find.descendant(
          of: find.byType(AppDivider),
          matching: find.byType(Padding),
        ),
      );
      expect(padding.padding, const EdgeInsets.only(left: 12));

      final box = tester.getSize(
        find.descendant(
          of: find.byType(AppDivider),
          matching: find.byType(Container),
        ),
      );
      expect(box.height, 1);
    });

    testWidgets('SectionHeader shouts its text', (tester) async {
      await _pump(tester, const SectionHeader('Export'));
      expect(find.text('EXPORT'), findsOneWidget);
    });
  });

  group('light and dark', () {
    for (final (name, theme) in [
      ('dark', AppTheme.darkTheme),
      ('light', AppTheme.lightTheme),
    ]) {
      testWidgets('the kit builds in $name without an exception', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ListView(
                children: [
                  const AppCard(child: Text('card')),
                  const AppDivider(),
                  const SectionHeader('header'),
                  const TagChip(label: 'tag', selected: true),
                  const TwoLineLabel(
                    text: 'two line',
                    style: TextStyle(fontSize: 12),
                  ),
                  const EmptyStateHint(
                    icon: PhosphorIconsRegular.shieldCheck,
                    text: 'hint',
                  ),
                  StepperRow(
                    label: 'step',
                    value: 2,
                    min: 1,
                    max: 3,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
