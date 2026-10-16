import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/ui/app_badge.dart';
import 'package:termphin/widgets/ui/app_card.dart';
import 'package:termphin/widgets/ui/bar_icon_button.dart';
import 'package:termphin/widgets/ui/empty_state.dart';
import 'package:termphin/widgets/ui/list_section_header.dart';
import 'package:termphin/widgets/ui/settings_controls.dart';
import 'package:termphin/widgets/ui/settings_tile.dart';
import 'package:termphin/widgets/ui/tag_chip.dart';

import '../../support/test_app.dart';

enum _Fruit { apple, banana, orange }

Future<void> _pump(WidgetTester tester, Widget child) async {
  await pumpTestApp(tester, Scaffold(body: child));
  await tester.pumpAndSettle();
}

void main() {
  group('AppCard', () {
    testWidgets('a segment that is not last leaves its bottom edge open', (
      tester,
    ) async {
      await _pump(
        tester,
        Column(
          children: [
            AppCard.segment(first: true, last: false, child: const Text('a')),
            AppCard.segment(first: false, last: true, child: const Text('b')),
          ],
        ),
      );

      BoxDecoration decorationOf(String text) {
        final box = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.text(text),
                matching: find.byType(DecoratedBox),
              )
              .last,
        );
        return box.decoration as BoxDecoration;
      }

      final top = decorationOf('a');
      final bottom = decorationOf('b');
      expect((top.border! as Border).bottom, BorderSide.none);
      expect(top.borderRadius, isA<BorderRadius>());
      expect((top.borderRadius! as BorderRadius).bottomLeft, Radius.zero);
      expect((bottom.border! as Border).bottom, isNot(BorderSide.none));
      expect((bottom.borderRadius! as BorderRadius).topLeft, Radius.zero);
    });

    testWidgets('onTap fires when tapped', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        AppCard(onTap: () => tapped = true, child: const Text('Card')),
      );

      await tester.tap(find.text('Card'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('selected: true paints border in primary', (tester) async {
      await _pump(
        tester,
        AppCard(selected: true, onTap: () {}, child: const Text('Selected')),
      );

      final ink = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = ink.decoration as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.border!.top.color, _getContextColors(tester).primary);
    });

    testWidgets(
      'plain card in dark palette has no border, in light has surfaceBorder',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(body: AppCard(child: Text('Dark Card'))),
          ),
        );
        await tester.pumpAndSettle();

        final darkContainer = tester.widget<Container>(
          find.descendant(
            of: find.byType(AppCard),
            matching: find.byType(Container),
          ),
        );
        final darkDecoration = darkContainer.decoration as BoxDecoration;
        expect(darkDecoration.border, isNull);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: AppCard(child: Text('Light Card'))),
          ),
        );
        await tester.pumpAndSettle();

        final lightContainer = tester.widget<Container>(
          find.descendant(
            of: find.byType(AppCard),
            matching: find.byType(Container),
          ),
        );
        final lightDecoration = lightContainer.decoration as BoxDecoration;
        expect(lightDecoration.border, isNotNull);
      },
    );

    testWidgets(
      'elevated: true uses surfaceElevated and has border in dark too',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: AppCard(
                elevated: true,
                onTap: () {},
                child: const Text('Elevated'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ink = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(AppCard),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final decoration = ink.decoration! as BoxDecoration;
        expect(decoration.border, isNotNull);
      },
    );
  });

  group('AppBadge', () {
    testWidgets('count(7) renders correct values', (tester) async {
      await _pump(tester, const AppBadge.count(7));

      expect(find.text('7'), findsOneWidget);

      final badge = tester.widget<AppBadge>(find.byType(AppBadge));
      expect(badge.count, 7);
      expect(badge.label, '7');
    });

    testWidgets('every BadgeTone value builds without error', (tester) async {
      for (final tone in BadgeTone.values) {
        await _pump(tester, AppBadge('Test', tone: tone));
        expect(find.text('Test'), findsOneWidget);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('icon: renders an Icon', (tester) async {
      await _pump(
        tester,
        const AppBadge('New', icon: PhosphorIconsRegular.star),
      );

      expect(find.byIcon(PhosphorIconsRegular.star), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
    });
  });

  group('TagChip', () {
    testWidgets('a tappable chip splashes and honours minHeight', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        Center(
          child: TagChip(
            label: 'CTRL',
            selected: false,
            minHeight: 38,
            onTap: () => taps++,
          ),
        ),
      );

      expect(find.byType(InkWell), findsOneWidget);
      expect(tester.getSize(find.byType(TagChip)).height, 38);
      await tester.tap(find.text('CTRL'));
      expect(taps, 1);
    });

    testWidgets('trailing is rendered', (tester) async {
      await _pump(
        tester,
        const TagChip(
          label: 'Tag',
          selected: true,
          trailing: IconButton(
            icon: Icon(PhosphorIconsRegular.x),
            onPressed: null,
          ),
        ),
      );

      expect(find.byIcon(PhosphorIconsRegular.x), findsOneWidget);
    });

    testWidgets('solid: true, selected: true fills with primary', (
      tester,
    ) async {
      await _pump(
        tester,
        const TagChip(label: 'Solid', selected: true, solid: true),
      );

      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, _getContextColors(tester).primary);
    });

    testWidgets('solid: true, selected: false does NOT fill with primary', (
      tester,
    ) async {
      await _pump(
        tester,
        const TagChip(label: 'NotSolid', selected: false, solid: true),
      );

      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNot(_getContextColors(tester).primary));
    });
  });

  group('SettingsCheckboxTile', () {
    testWidgets('tapping toggles via onChanged(true)', (tester) async {
      var value = false;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SettingsCheckboxTile(
            title: 'Toggle',
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(value, isTrue);
    });
  });

  group('SettingsTile', () {
    testWidgets('trailingWidget shows instead of chevron', (tester) async {
      await _pump(
        tester,
        SettingsTile(
          title: 'Row',
          trailingWidget: const Text('Custom'),
          onTap: () {},
        ),
      );

      expect(find.text('Custom'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon && widget.icon == PhosphorIconsFill.caretRight,
        ),
        findsNothing,
      );
    });

    testWidgets('dense: true title uses fontSize AppTheme.font14', (
      tester,
    ) async {
      await _pump(tester, const SettingsTile(title: 'Dense', dense: true));

      final titleText = tester.widget<Text>(
        find
            .descendant(of: find.byType(ListTile), matching: find.byType(Text))
            .first,
      );
      expect(titleText.style?.fontSize, AppTheme.font14);
    });
  });

  group('SettingsDropdownField', () {
    testWidgets(
      'opening and picking an entry calls onChanged with enum value',
      (tester) async {
        _Fruit? selected = _Fruit.apple;
        await _pump(
          tester,
          StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: SettingsDropdownField<_Fruit>(
                label: 'Fruit',
                value: selected!,
                labels: const {
                  _Fruit.apple: 'Apple',
                  _Fruit.banana: 'Banana',
                  _Fruit.orange: 'Orange',
                },
                onChanged: (v) => setState(() => selected = v),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Apple'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Banana'));
        await tester.pumpAndSettle();

        expect(selected, _Fruit.banana);
      },
    );
  });

  group('EmptyStatePanel', () {
    testWidgets('tone: EmptyStateTone.error paints icon in error', (
      tester,
    ) async {
      late BuildContext context;
      await pumpTestApp(
        tester,
        Builder(
          builder: (c) {
            context = c;
            return const EmptyStatePanel(
              icon: PhosphorIconsRegular.warning,
              title: 'Error',
              tone: EmptyStateTone.error,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(
        find.byIcon(PhosphorIconsRegular.warning),
      );
      expect(icon.color, context.colors.error);
    });

    testWidgets('compact: true builds', (tester) async {
      await _pump(
        tester,
        const EmptyStatePanel(
          icon: PhosphorIconsRegular.shieldCheck,
          title: 'Compact',
          compact: true,
        ),
      );

      expect(find.text('Compact'), findsOneWidget);
    });
  });

  group('BarIconButton', () {
    testWidgets('onPressed: null is disabled', (tester) async {
      await _pump(
        tester,
        const BarIconButton(
          icon: PhosphorIconsRegular.arrowLeft,
          tooltip: 'Back',
          onPressed: null,
        ),
      );

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('has 30x30 tap target', (tester) async {
      await _pump(
        tester,
        BarIconButton(
          icon: PhosphorIconsRegular.arrowLeft,
          tooltip: 'Back',
          onPressed: () {},
        ),
      );

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.constraints?.maxWidth, 30);
      expect(button.constraints?.maxHeight, 30);
    });
  });

  group('ListSectionHeader', () {
    testWidgets('count: 3 shows AppBadge with count 3', (tester) async {
      await _pump(tester, const ListSectionHeader(title: 'Items', count: 3));

      final badge = tester.widget<AppBadge>(find.byType(AppBadge));
      expect(badge.count, 3);
    });

    testWidgets('action fires onPressed', (tester) async {
      var pressed = false;
      await _pump(
        tester,
        ListSectionHeader(
          title: 'Items',
          onAdd: () => pressed = true,
          addTooltip: 'Add',
        ),
      );

      await tester.tap(find.byIcon(PhosphorIconsRegular.plus));
      await tester.pumpAndSettle();

      expect(pressed, isTrue);
    });
  });
}

AppColors _getContextColors(WidgetTester tester) {
  late BuildContext context;
  tester.widget<Builder>(find.byWidgetPredicate((w) => w is Builder).first);
  tester.element(find.byType(Scaffold)).visitAncestorElements((e) {
    context = e as BuildContext;
    return true;
  });
  return context.colors;
}
