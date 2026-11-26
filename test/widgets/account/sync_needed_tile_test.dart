import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/providers/account_provider.dart';
import 'package:termphin/providers/sync_provider.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/sync/sync_coordinator.dart';
import 'package:termphin/services/sync/sync_service.dart';
import 'package:termphin/widgets/account/sync_needed_tile.dart';

import '../../support/sync_fakes.dart';
import '../../support/test_app.dart';

class _Account extends AccountNotifier {
  _Account(this.user);

  final AccountUser? user;

  @override
  AccountUser? build() => user;
}

void main() {
  final t = AppLocale.en.buildSync();
  const message = 'Needs sync to work everywhere';
  late SyncCoordinator coordinator;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final service = SyncService(
      cloud: FakeSyncCloud(),
      vault: FakeSyncVault(),
      local: FakeSyncLocal(),
      uid: () => 'u1',
    );
    coordinator = SyncCoordinator(service: service, reload: () async {});
  });

  Future<void> pump(WidgetTester tester, {AccountUser? user}) async {
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(() => _Account(user)),
        syncCoordinatorProvider.overrideWithValue(coordinator),
      ],
    );
    addTearDown(container.dispose);
    await pumpTestApp(
      tester,
      const Scaffold(body: SyncNeededTile(message: message)),
      container: container,
    );
    await tester.pumpAndSettle();
  }

  const signedIn = AccountUser(uid: 'u1', provider: AccountProvider.google);

  testWidgets('shows the note while sync is not running here', (tester) async {
    await pump(tester, user: signedIn);

    expect(find.text(t.account.sync.needsSyncTitle), findsOneWidget);
    expect(find.text(message), findsOneWidget);
  });

  testWidgets('shows nothing while sync runs on this device', (tester) async {
    coordinator.running.value = true;
    await pump(tester, user: signedIn);

    expect(find.text(t.account.sync.needsSyncTitle), findsNothing);
    expect(find.text(message), findsNothing);
  });

  testWidgets('shows nothing without an account', (tester) async {
    await pump(tester);

    expect(find.text(t.account.sync.needsSyncTitle), findsNothing);
    expect(find.text(message), findsNothing);
  });
}
