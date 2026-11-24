import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:termphin/services/platform/app_updater.dart';
import 'package:termphin/services/platform/appcast_parser.dart';
import 'package:termphin/services/platform/linux_self_updater.dart';
import 'package:termphin/widgets/window/desktop_status_bar.dart';
import 'package:termphin/widgets/window/update_download_dialog.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets(
    'UpdateDownloadDialog shows progress bar, verifying state, and cancel',
    (tester) async {
      final progress = ValueNotifier<LinuxUpdateProgress>(
        const LinuxUpdateProgress(
          stage: LinuxUpdateStage.downloading,
          received: 5 * 1024 * 1024,
          total: 10 * 1024 * 1024,
        ),
      );
      addTearDown(progress.dispose);
      var cancelled = false;

      await pumpTestApp(
        tester,
        Scaffold(
          body: UpdateDownloadDialog(
            version: '1.17.0',
            progress: progress,
            onCancel: () => cancelled = true,
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('5.0 / 10.0 MB (50%)'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      expect(cancelled, isTrue);

      progress.value = const LinuxUpdateProgress(
        stage: LinuxUpdateStage.verifying,
        received: 10 * 1024 * 1024,
        total: 10 * 1024 * 1024,
      );
      await tester.pump();
      expect(find.text('Verifying signature…'), findsOneWidget);
    },
  );

  testWidgets('DesktopStatusBar shows version and reacts to available updates', (
    tester,
  ) async {
    AppUpdater.instance.availableUpdate.value = null;
    addTearDown(() => AppUpdater.instance.availableUpdate.value = null);

    await pumpTestApp(
      tester,
      Scaffold(
        bottomNavigationBar: DesktopStatusBar(
          navigatorContext: () => null,
          packageInfoLoader: () async => PackageInfo(
            appName: 'Termphin',
            packageName: 'termphin',
            version: '1.16.1',
            buildNumber: '900',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('v1.16.1 (900)'), findsOneWidget);
    expect(find.text('Update to 1.17.0'), findsNothing);

    AppUpdater.instance.availableUpdate.value = AppcastEntry(
      version: '1.17.0',
      buildNumber: '901',
      downloadUrl: Uri.parse('https://example.com/Termphin.AppImage'),
      edSignature: 'sig==',
    );
    await tester.pump();

    expect(find.text('Update to 1.17.0'), findsOneWidget);
  });
}
