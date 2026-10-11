import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/theme/theme.dart';

Future<void> pumpTestApp(
  WidgetTester tester,
  Widget child, {
  ProviderContainer? container,
}) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final app = TranslationProvider(
    child: MaterialApp(theme: AppTheme.darkTheme, home: child),
  );
  await tester.pumpWidget(
    container == null
        ? ProviderScope(child: app)
        : UncontrolledProviderScope(container: container, child: app),
  );
}
