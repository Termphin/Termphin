import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/ui/app_dropdown.dart';

import '../../support/test_app.dart';

void main() {
  group('menuEdgeNudge', () {
    const width = 252.0;
    const screen = 390.0;

    double nudge(Rect button, {DropdownDirection? direction}) => menuEdgeNudge(
      button: button,
      width: width,
      screenWidth: screen,
      direction: direction ?? DropdownDirection.left,
      offsetX: 0,
    );

    test('a menu that would reach past the left edge is pulled in', () {
      final n = nudge(const Rect.fromLTWH(172, 0, 28, 28));
      expect(200 - width + n, kMenuScreenMargin);
    });

    test('and past the right edge, pushed back', () {
      final n = nudge(
        const Rect.fromLTWH(300, 0, 28, 28),
        direction: DropdownDirection.right,
      );
      expect(300 + n + width, screen - kMenuScreenMargin);
    });

    test('one already clear of both sides is left alone', () {
      expect(nudge(const Rect.fromLTWH(320, 0, 28, 28)), 0);
    });

    test('a screen too narrow for the margin gives up rather than throw', () {
      expect(
        menuEdgeNudge(
          button: const Rect.fromLTWH(0, 0, 28, 28),
          width: 252,
          screenWidth: 260,
          direction: DropdownDirection.left,
          offsetX: 0,
        ),
        0,
      );
    });
  });

  group('menuMaxHeight', () {
    const button = Rect.fromLTWH(300, 40, 28, 28);

    double? maxHeight({double screen = 844, double inset = 0}) => menuMaxHeight(
      button: button,
      screenHeight: screen,
      bottomInset: inset,
      offsetY: -6,
    );

    test('is the room under the button, short of the margin', () {
      expect(maxHeight(), 844 - kMenuScreenMargin - 74);
    });

    test('an open keyboard takes its share', () {
      expect(maxHeight(inset: 300), 844 - 300 - kMenuScreenMargin - 74);
    });

    test('too little room leaves placement to the package', () {
      expect(maxHeight(screen: 200), isNull);
    });
  });

  testWidgets('a menu opened by the left edge keeps clear of it', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, top: 40),
            child: AppActionDropdown<int>(
              items: const [
                DropdownItem(
                  value: 1,
                  intrinsicHeight: true,
                  child: AppDropdownItem(label: 'First'),
                ),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(PhosphorIconsRegular.dotsThreeVertical));
    await tester.pumpAndSettle();

    final label = tester.getRect(find.text('First')).left;
    expect(label - 12, closeTo(kMenuScreenMargin, 1));
  });

  testWidgets('a menu too tall for the screen stays under its button and '
      'scrolls', (tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 300, top: 40),
            child: AppActionDropdown<int>(
              items: [
                for (var i = 0; i < 8; i++)
                  DropdownItem(
                    value: i,
                    intrinsicHeight: true,
                    child: AppDropdownItem(label: 'Item $i'),
                  ),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    final button = tester.getRect(
      find.byIcon(PhosphorIconsRegular.dotsThreeVertical),
    );

    await tester.tap(find.byIcon(PhosphorIconsRegular.dotsThreeVertical));
    await tester.pumpAndSettle();

    final menu = tester.getRect(
      find.ancestor(of: find.text('Item 0'), matching: find.byType(ListView)),
    );
    expect(menu.top, greaterThanOrEqualTo(button.bottom));
    expect(menu.bottom, lessThanOrEqualTo(390 - kMenuScreenMargin));

    await tester.drag(find.text('Item 3'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Item 7')).bottom,
      lessThanOrEqualTo(menu.bottom),
    );
  });

  group('AppDropdownItem', () {
    Icon iconOf(WidgetTester tester) => tester.widget<Icon>(find.byType(Icon));

    testWidgets('its icon is quieter than its label', (tester) async {
      late BuildContext context;
      await pumpTestApp(
        tester,
        Builder(
          builder: (c) {
            context = c;
            return const AppDropdownItem(
              icon: PhosphorIconsRegular.pencilSimple,
              label: 'Rename',
            );
          },
        ),
      );

      expect(iconOf(tester).size, 18);
      expect(iconOf(tester).color, context.colors.textSecondary);
      expect(
        tester.widget<Text>(find.text('Rename')).style?.color,
        isNot(context.colors.textSecondary),
      );
    });

    testWidgets('a coloured entry colours both', (tester) async {
      await pumpTestApp(
        tester,
        const AppDropdownItem(
          icon: PhosphorIconsRegular.trash,
          label: 'Delete',
          color: Colors.red,
        ),
      );

      expect(iconOf(tester).color, Colors.red);
      expect(tester.widget<Text>(find.text('Delete')).style?.color, Colors.red);
    });
  });
}
