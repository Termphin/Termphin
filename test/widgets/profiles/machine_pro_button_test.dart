import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/account_provider.dart';
import 'package:termphin/providers/relay_keys_provider.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/push/relay_key_store.dart';
import 'package:termphin/widgets/profiles/machine_pro_button.dart';

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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, {required bool pro}) async {
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_Account.new),
        relayKeysProvider.overrideWith(
          (ref) => Stream.value(const [
            RelayServer(keyId: 'k1', label: 'web', profileId: 'web'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpTestApp(
      tester,
      Scaffold(
        body: Row(
          children: [
            MachineProButton(profile: profile('web'), pro: ValueNotifier(pro)),
            MachineProButton(profile: profile('db'), pro: ValueNotifier(pro)),
          ],
        ),
      ),
      container: container,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the bell is lit on a machine with something on, dim on one with nothing',
    (tester) async {
      await pump(tester, pro: true);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('machinePro-web')),
          matching: find.byIcon(PhosphorIconsFill.bellSimple),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('machinePro-db')),
          matching: find.byIcon(PhosphorIconsRegular.bellSimple),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('without Pro there is no bell', (tester) async {
    await pump(tester, pro: false);
    expect(find.byKey(const ValueKey('machinePro-web')), findsNothing);
  });

  testWidgets('opening the bell menu shows one check per enabled feature', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_Account.new),
        relayKeysProvider.overrideWith(
          (ref) => Stream.value(const [
            RelayServer(
              keyId: 'k1',
              label: 'web',
              profileId: 'web',
              notify: true,
              live: true,
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpTestApp(
      tester,
      Scaffold(
        body: MachineProButton(
          profile: profile('web'),
          pro: ValueNotifier(true),
        ),
      ),
      container: container,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('machinePro-web')));
    await tester.pumpAndSettle();
    expect(find.byIcon(PhosphorIconsRegular.check), findsNWidgets(2));
  });
}
