import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/widgets/pro/feature_demos.dart';

import '../../support/test_app.dart';

void main() {
  for (final kind in FeatureDemoKind.values) {
    for (final look in PhoneLook.values) {
      testWidgets('the ${kind.name} demo runs a whole loop on '
          '${look.name} without a layout error', (tester) async {
        await pumpTestApp(
          tester,
          Center(
            child: FeatureDemo(kind: kind, look: look),
          ),
        );

        for (var second = 0; second < 13; second++) {
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull, reason: 'at $second s');
        }
        expect(
          tester.getSize(find.byType(FeatureDemo)).height,
          FeatureDemo.height,
        );
      });
    }
  }

  testWidgets('every picture a demo draws is in the bundle', (tester) async {
    for (final look in PhoneLook.values) {
      for (final kind in FeatureDemoKind.values) {
        await pumpTestApp(
          tester,
          FeatureDemo(key: ValueKey('$look$kind'), kind: kind, look: look),
        );
        await tester.pump(const Duration(seconds: 6));
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          final name = (image.image as AssetImage).assetName;
          expect(name, startsWith('assets/feature_demos/${look.name}/'));
          final bytes = await tester.runAsync(() => rootBundle.load(name));
          expect(bytes!.lengthInBytes, greaterThan(0), reason: name);
        }
      }
    }
  });

  testWidgets('notifications arrive one by one, newest on top', (tester) async {
    await pumpTestApp(
      tester,
      const FeatureDemo(
        kind: FeatureDemoKind.notifications,
        look: PhoneLook.pixel,
      ),
    );

    await tester.pump(const Duration(milliseconds: 1000));
    expect(_shown(tester, 'note-dump'), isTrue);
    expect(_shown(tester, 'note-deploy-now'), isFalse);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(_shown(tester, 'note-deploy-now'), isTrue);
    expect(_shown(tester, 'note-agent'), isFalse);

    await tester.pump(const Duration(milliseconds: 2500));
    expect(_shown(tester, 'note-agent'), isTrue);
    expect(_opacityOf(tester, 'note-deploy-now'), 0);
    expect(_shown(tester, 'note-deploy'), isTrue);
    expect(
      tester.getTopLeft(_picture('note-agent')).dy,
      lessThan(tester.getTopLeft(_picture('note-dump')).dy),
    );
  });

  testWidgets('live status is the real home screen, still, in the theme', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      const Center(
        child: FeatureDemo(kind: FeatureDemoKind.live, look: PhoneLook.iphone),
      ),
    );

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('liveScreenshot')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (image.image as AssetImage).assetName,
      'assets/feature_demos/iphone/live-dark.webp',
    );
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('with less motion asked for it holds one full frame', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: FeatureDemo(
          kind: FeatureDemoKind.notifications,
          look: PhoneLook.iphone,
        ),
      ),
    );

    expect(tester.binding.transientCallbackCount, 0);
    expect(_shown(tester, 'note-agent'), isTrue);
    expect(_opacityOf(tester, 'note-deploy'), 1);
  });
}

Finder _picture(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName.endsWith('/$name.webp'),
);

/// The opacity the picture called [name] is drawn with: every [Opacity]
/// above it multiplied together.
double _opacityOf(WidgetTester tester, String name) => tester
    .widgetList<Opacity>(
      find.ancestor(of: _picture(name), matching: find.byType(Opacity)),
    )
    .fold(1.0, (opacity, widget) => opacity * widget.opacity);

/// Whether the notice drawn as [name] has fully come in.
bool _shown(WidgetTester tester, String name) =>
    _picture(name).evaluate().isNotEmpty && _opacityOf(tester, name) > 0.99;
