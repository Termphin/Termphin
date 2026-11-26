import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/account_provider.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/push/machine_switches.dart';
import 'package:termphin/services/push/notify_prefs_store.dart';
import 'package:termphin/services/push/relay_key_store.dart';
import 'package:termphin/widgets/profiles/machine_pro_button.dart';
import 'package:termphin/widgets/settings/pro_machines_list.dart';
import 'package:termphin/widgets/ui/app_badge.dart';

import '../../support/test_app.dart';

class _Account extends AccountNotifier {
  @override
  AccountUser? build() =>
      const AccountUser(uid: 'u1', provider: AccountProvider.google);
}

SshProfile profile(String id) => SshProfile(
  id: id,
  name: id,
  host: '$id.example',
  port: 22,
  username: 'me',
  authMethod: AuthMethod.privateKey,
  createdAt: DateTime.utc(2026),
);

void main() {
  final profiles = [
    profile('web'),
    profile('db'),
    profile('pi'),
    profile('box'),
  ];
  const keys = [
    RelayServer(keyId: 'k1', label: 'web', profileId: 'web', live: true),
    RelayServer(keyId: 'k2', label: 'db', profileId: 'db', live: false),
  ];

  test('each list holds only the machines with its feature on, by name', () {
    const pending = {'pi': MachineSwitchChange(live: true)};
    expect(
      machinesWith(
        MachineFeature.notifications,
        profiles,
        pending: pending,
        keys: keys,
      ).map((p) => p.id),
      ['db', 'web'],
    );
    expect(
      machinesWith(
        MachineFeature.live,
        profiles,
        pending: pending,
        keys: keys,
      ).map((p) => p.id),
      ['pi', 'web'],
    );
  });

  test(
    'a machine switched off here leaves its list before the server hears',
    () {
      expect(
        machinesWith(
          MachineFeature.notifications,
          profiles,
          pending: const {'web': MachineSwitchChange(notify: false)},
          keys: keys,
        ).map((p) => p.id),
        ['db'],
      );
    },
  );

  testWidgets('This device badge uses the accent tone', (tester) async {
    final container = ProviderContainer(
      overrides: [accountProvider.overrideWith(_Account.new)],
    );
    addTearDown(container.dispose);
    await pumpTestApp(
      tester,
      Scaffold(
        body: ProDevicesList(
          ownId: 'd1',
          devices: Stream.value(const [
            NotifyDestination(
              id: 'd1',
              platform: 'android',
              kind: NotifyDeviceKind.phone,
            ),
          ]),
        ),
      ),
      container: container,
    );
    await tester.pumpAndSettle();
    final badge = tester.widget<AppBadge>(find.byType(AppBadge));
    expect(badge.tone, BadgeTone.accent);
  });
}
