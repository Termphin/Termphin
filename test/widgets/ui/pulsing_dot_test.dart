import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/widgets/ui/pulsing_dot.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool reduceMotion}) =>
      tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: PulsingDot(color: Color(0xFFEBB55A), size: 10),
          ),
        ),
      );

  testWidgets('it breathes', (tester) async {
    await pump(tester, reduceMotion: false);
    final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
    final before = fade.opacity.value;
    await tester.pump(const Duration(milliseconds: 550));
    expect(fade.opacity.value, isNot(before));
  });

  testWidgets('with animations off it stays still', (tester) async {
    await pump(tester, reduceMotion: true);
    expect(find.byType(FadeTransition), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
