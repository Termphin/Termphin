import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/theme/theme.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Size? minimumSize(ButtonStyle? style) => style?.minimumSize?.resolve({});

  test('a desktop gets tight corners, compact density and short buttons', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final theme = AppTheme.themeFor(AppColors.dark);

    expect(AppTheme.radiusSm, 6);
    expect(AppTheme.radiusXxl, lessThanOrEqualTo(14));
    expect(theme.visualDensity, VisualDensity.compact);
    expect(theme.materialTapTargetSize, MaterialTapTargetSize.shrinkWrap);
    expect(
      minimumSize(theme.filledButtonTheme.style)?.height,
      AppTheme.desktopControlHeight,
    );
    expect(
      minimumSize(theme.outlinedButtonTheme.style)?.height,
      AppTheme.desktopControlHeight,
    );
    expect(theme.inputDecorationTheme.isDense, isTrue);
    expect(theme.scrollbarTheme.thickness?.resolve({}), 6);
    expect(theme.scrollbarTheme.thickness?.resolve({WidgetState.hovered}), 10);
    expect(theme.tooltipTheme.waitDuration, isNotNull);
  });

  test('a phone keeps the thumb-sized scale', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final theme = AppTheme.themeFor(AppColors.dark);

    expect(AppTheme.radiusSm, 14);
    expect(theme.visualDensity, isNot(VisualDensity.compact));
    expect(minimumSize(theme.filledButtonTheme.style)?.height, 48);
    expect(theme.inputDecorationTheme.isDense, isFalse);
    expect(theme.scrollbarTheme.thickness, isNull);
  });

  testWidgets('the terminal is drawn at the size set, not the desktop\'s '
      'smaller interface scale', (tester) async {
    late TextScaler terminal;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(AppTheme.desktopTextScale),
        ),
        child: Builder(
          builder: (context) {
            terminal = AppTheme.terminalTextScaler(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(terminal.scale(14), closeTo(14, 0.001));
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
}
