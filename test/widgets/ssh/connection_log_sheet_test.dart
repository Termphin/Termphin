import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/ssh_connection_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/services/app/identity_anonymizer.dart';
import 'package:termphin/services/settings/anonymize_setting.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/ssh/connection_log_sheet.dart';

import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

void main() {
  late FakeSshBackend backend;
  late FakeRemoteAgentService agent;
  late SshSessionManager manager;
  late ProviderContainer container;
  late SshProfile profile;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
    profile = profileFixture();
    backend = FakeSshBackend();
    agent = FakeRemoteAgentService(backend);
    manager = SshSessionManager.test(
      remoteAgentService: agent,
      serviceFactory: backend.createService,
    );
    container = ProviderContainer.test(
      overrides: [sshSessionManagerProvider.overrideWithValue(manager)],
    );
  });

  tearDown(() => manager.dispose());

  Future<void> openSheet(WidgetTester tester, (String, SshProfile) session) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showConnectionLogSheet(context, session),
            child: const Text('open'),
          ),
        ),
      ),
      container: container,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the raw connection log when anonymize is off', (
    tester,
  ) async {
    backend.connectionMessages = [
      'Connecting to ${profile.host}:${profile.port}',
    ];
    final session = ('session-1', profile);
    await container.read(sshConnectionProvider(session).notifier).connect();

    await openSheet(tester, session);

    expect(
      find.textContaining('Connecting to ${profile.host}:${profile.port}'),
      findsOneWidget,
    );
  });

  testWidgets('scrubs the real host and username out of the log', (
    tester,
  ) async {
    await anonymizeSetting.set(true);
    addTearDown(() => anonymizeSetting.set(false));
    backend.connectionMessages = [
      'Connecting to ${profile.host}:${profile.port}',
    ];
    final session = ('session-1', profile);
    await container.read(sshConnectionProvider(session).notifier).connect();

    await openSheet(tester, session);

    expect(
      find.textContaining(IdentityAnonymizer.host(profile.id)),
      findsOneWidget,
    );
    expect(find.textContaining(profile.host), findsNothing);
  });
}
