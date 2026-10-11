import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/fast_upload_settings_screen.dart';
import 'package:termphin/services/analytics/analytics_config.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/upload_settings.dart';
import 'package:termphin/widgets/sftp/upload_progress_bar.dart';
import 'package:termphin/widgets/ui/large_title_scaffold.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  group('FastUploadSettingsScreen', () {
    Future<void> pump(WidgetTester tester) async {
      await pumpTestApp(tester, const FastUploadSettingsScreen());
      await tester.pumpAndSettle();
    }

    testWidgets('opens on whatever destination is stored', (tester) async {
      await uploadDestinationSetting.set(UploadDestination.currentDirectory);
      await pump(tester);

      expect(find.text(t.settings.fastUpload), findsWidgets);
      expect(find.text(t.settings.uploadDestination), findsOneWidget);
    });

    testWidgets('writes a new destination straight through to the setting', (
      tester,
    ) async {
      await pump(tester);
      final other = UploadDestination.values.firstWhere(
        (d) => d != uploadDestinationSetting.value,
      );

      await tester.tap(find.text(labelFor(uploadDestinationSetting.value, t)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(labelFor(other, t)).last);
      await tester.pumpAndSettle();

      expect(uploadDestinationSetting.value, other);
    });

    testWidgets('auto-paste is off until it is deliberately turned on', (
      tester,
    ) async {
      await pump(tester);

      expect(uploadAutoPasteSetting.value, isFalse);
      expect(find.text(t.settings.uploadAutoPaste), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    });

    testWidgets('the auto-paste switch writes straight through', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(uploadAutoPasteSetting.value, isTrue);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(uploadAutoPasteSetting.value, isFalse);
    });

    testWidgets('opens on a stored auto-paste of on', (tester) async {
      await uploadAutoPasteSetting.set(true);
      await pump(tester);

      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    });
  });

  group('LargeTitleHeader', () {
    testWidgets('shows its title and subtitle', (tester) async {
      await pumpTestApp(
        tester,
        const Scaffold(
          body: LargeTitleHeader(title: 'Fast upload', subtitle: 'How it goes'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fast upload'), findsOneWidget);
      expect(find.text('How it goes'), findsOneWidget);
    });

    testWidgets('works without a subtitle', (tester) async {
      await pumpTestApp(
        tester,
        const Scaffold(body: LargeTitleHeader(title: 'Only a title')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Only a title'), findsOneWidget);
    });
  });

  group('DesktopContentWidth', () {
    testWidgets('caps how wide the content runs', (tester) async {
      tester.view.physicalSize = const Size(2000, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DesktopContentWidth(
              maxWidth: 400,
              child: SizedBox.expand(key: Key('body')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byKey(const Key('body'))).width, 400);
    });

    testWidgets('leaves a narrow screen the full width it had', (tester) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DesktopContentWidth(
              maxWidth: 400,
              child: SizedBox.expand(key: Key('body')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byKey(const Key('body'))).width, 600);
    });
  });

  group('UploadProgressBar', () {
    testWidgets('shows nothing while there is no upload', (tester) async {
      final progress = ValueNotifier<UploadProgress?>(null);
      addTearDown(progress.dispose);

      await pumpTestApp(
        tester,
        Scaffold(
          body: Stack(
            children: [UploadProgressBar(progress: progress, onCancel: () {})],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.textContaining('B'), findsNothing);
    });

    testWidgets('reports bytes against the total once one is known', (
      tester,
    ) async {
      final progress = ValueNotifier<UploadProgress?>(
        const UploadProgress(bytes: 512, total: 2048),
      );
      addTearDown(progress.dispose);

      await pumpTestApp(
        tester,
        Scaffold(
          body: Stack(
            children: [UploadProgressBar(progress: progress, onCancel: () {})],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('512'), findsOneWidget);
    });

    testWidgets('fills in proportion to what is done', (tester) async {
      final progress = ValueNotifier<UploadProgress?>(
        const UploadProgress(bytes: 512, total: 2048),
      );
      addTearDown(progress.dispose);

      await pumpTestApp(
        tester,
        Scaffold(
          body: Stack(
            children: [UploadProgressBar(progress: progress, onCancel: () {})],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(bar.widthFactor, closeTo(0.25, 1e-9));
    });

    testWidgets('with no total there is nothing to fill', (tester) async {
      final progress = ValueNotifier<UploadProgress?>(
        const UploadProgress(bytes: 512),
      );
      addTearDown(progress.dispose);

      await pumpTestApp(
        tester,
        Scaffold(
          body: Stack(
            children: [UploadProgressBar(progress: progress, onCancel: () {})],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(bar.widthFactor, 0.0);
    });

    testWidgets('goes away again when the upload finishes', (tester) async {
      final progress = ValueNotifier<UploadProgress?>(
        const UploadProgress(bytes: 512, total: 2048),
      );
      addTearDown(progress.dispose);

      await pumpTestApp(
        tester,
        Scaffold(
          body: Stack(
            children: [UploadProgressBar(progress: progress, onCancel: () {})],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FractionallySizedBox), findsOneWidget);

      progress.value = null;
      await tester.pumpAndSettle();
      expect(find.byType(FractionallySizedBox), findsNothing);
    });
  });

  group('AnalyticsConfig', () {
    test('a build without a key sends nothing', () {
      final override = AnalyticsConfig.apiKeyOverride;
      addTearDown(() => AnalyticsConfig.apiKeyOverride = override);
      AnalyticsConfig.apiKeyOverride = null;
      expect(AnalyticsConfig.projectApiKey, isEmpty);
      expect(AnalyticsConfig.isConfigured, isFalse);
    });

    test('points at the EU host', () {
      expect(AnalyticsConfig.host, contains('eu.i.posthog.com'));
      expect(Uri.parse(AnalyticsConfig.host).scheme, 'https');
    });
  });
}

/// The dropdown labels each destination by, mirrored here so the test picks
/// the entry the user would.
String labelFor(UploadDestination destination, Translations t) =>
    switch (destination) {
      UploadDestination.tmp => t.settings.uploadDestinationTmp,
      UploadDestination.currentDirectory =>
        t.settings.uploadDestinationCurrentDir,
      UploadDestination.ask => t.settings.uploadDestinationAsk,
    };
