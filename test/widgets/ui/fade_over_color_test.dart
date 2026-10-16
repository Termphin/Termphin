import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/widgets/ui/fade_over_color.dart';

void main() {
  const color = Color(0xFF102030);

  Future<void> pump(WidgetTester tester, double opacity) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: FadeOverColor(
        opacity: opacity,
        color: color,
        child: const SizedBox(width: 10, height: 10),
      ),
    ),
  );

  Color cover(WidgetTester tester) => tester
      .widget<ColoredBox>(
        find.descendant(
          of: find.byType(FadeOverColor),
          matching: find.byType(ColoredBox),
        ),
      )
      .color;

  testWidgets('half way paints the colour at half strength, never a layer', (
    tester,
  ) async {
    await pump(tester, 0.5);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    expect(cover(tester).a, closeTo(0.5, 0.01));
  });

  testWidgets('fully shown leaves the child untouched', (tester) async {
    await pump(tester, 1);
    expect(cover(tester).a, 0);
  });

  testWidgets('fully faded does not paint the child at all', (tester) async {
    await pump(tester, 0);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
  });
}
