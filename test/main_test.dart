import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/app.dart';
import 'package:termphin/main.dart' as entrypoint;
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import 'support/secure_storage_channel.dart';

/// connectivity_plus has no implementation under `flutter test`, and the
/// network monitor subscribes to its event channel during startup.
void mockConnectivity() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => <String>['wifi'],
  );
  messenger.setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    MockStreamHandler.inline(
      onListen: (arguments, sink) => sink.success(<String>['wifi']),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots into the app with everything wired up', (tester) async {
    SharedPreferences.setMockInitialValues({
      terminalSettings.fontSize.key: 17.0,
    });
    mockSecureStorage();
    mockConnectivity();
    PackageInfo.setMockInitialValues(
      appName: 'Termphin',
      packageName: 'termphin',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    expect(SshSessionManager.instance.hostKeyPrompt, isNull);
    expect(SshSessionManager.instance.keyboardInteractivePrompt, isNull);

    await tester.runAsync(entrypoint.main);
    await tester.pump();

    expect(find.byType(SshClientApp), findsOneWidget);

    expect(SshSessionManager.instance.hostKeyPrompt, isNotNull);
    expect(SshSessionManager.instance.keyboardInteractivePrompt, isNotNull);

    expect(terminalSettings.fontSize.value, 17);
  });

  testWidgets('a second entry re-attaches instead of initialising twice', (
    tester,
  ) async {
    mockConnectivity();
    await tester.runAsync(entrypoint.main);
    await tester.pump();

    expect(find.byType(SshClientApp), findsOneWidget);
  });

  test('loadAppSettings is what main relies on being done first', () async {
    SharedPreferences.setMockInitialValues({
      terminalSettings.fontSize.key: 19.0,
    });
    SharedPreferences.resetStatic();
    await loadAppSettings();
    expect(terminalSettings.fontSize.value, 19);
  });
}
