import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/utils/platform_info.dart';

void main() {
  final phone = TargetPlatformVariant.only(TargetPlatform.android);

  Future<bool> wideAt(WidgetTester tester, Size size) async {
    late bool wide;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (context) {
            wide = isWideLayout(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return wide;
  }

  testWidgets('a phone turned to landscape gets the sidebar', (tester) async {
    expect(await wideAt(tester, const Size(915, 412)), isTrue);
  }, variant: phone);

  testWidgets('a portrait phone keeps the bottom bar', (tester) async {
    expect(await wideAt(tester, const Size(412, 915)), isFalse);
  }, variant: phone);

  testWidgets('half a split screen keeps the bottom bar even when it is wider '
      'than tall, or the sidebar would leave the screen a sliver', (
    tester,
  ) async {
    expect(await wideAt(tester, const Size(412, 400)), isFalse);
  }, variant: phone);
}
