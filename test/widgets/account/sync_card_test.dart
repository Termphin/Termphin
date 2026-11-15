import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/providers/sync_provider.dart';
import 'package:termphin/services/pro/pro_service.dart';
import 'package:termphin/services/sync/sync_coordinator.dart';
import 'package:termphin/services/sync/sync_service.dart';
import 'package:termphin/widgets/account/sync_card.dart';

import '../../support/sync_fakes.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();
  late FakeSyncCloud cloud;
  late FakeSyncVault vault;
  late SyncService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = FakeSyncCloud();
    vault = FakeSyncVault();
    service = SyncService(
      cloud: cloud,
      vault: vault,
      local: FakeSyncLocal(),
      uid: () => 'u1',
    );
  });

  Future<void> show(
    WidgetTester tester, {
    Future<bool> Function()? confirmPro,
  }) async {
    await pumpTestApp(
      tester,
      SyncCard(
        service: service,
        coordinator: SyncCoordinator(service: service, reload: () async {}),
        confirmPro: confirmPro,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> typeInDialog(
    WidgetTester tester,
    String text,
    String button,
  ) async {
    await tester.enterText(find.byType(TextFormField).last, text);
    await tester.tap(find.text(button).last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('off, it explains itself and offers to turn on', (tester) async {
    await show(tester);

    expect(find.text(t.account.sync.off), findsOneWidget);
    expect(find.text(t.account.sync.turnOn), findsOneWidget);
  });

  testWidgets('an account without Pro is told by a pill, not an error', (
    tester,
  ) async {
    cloud.refusal = const SyncException(SyncFailure.notPro);
    await show(tester);

    expect(find.text(t.account.sync.failure.notPro), findsNothing);
    expect(find.text(t.account.pro.badge), findsOneWidget);
    expect(find.text(t.account.sync.turnOn), findsOneWidget);
  });

  group('Pro the server has not heard of yet', () {
    setUp(() => ProService.instance.active.value = true);
    tearDown(() => ProService.instance.active.value = false);

    testWidgets('is waited for, and then sync can be turned on', (
      tester,
    ) async {
      cloud.refusal = const SyncException(SyncFailure.notPro);
      await show(
        tester,
        confirmPro: () async {
          cloud.refusal = null;
          return true;
        },
      );

      expect(find.text(t.account.pro.badge), findsNothing);
      expect(find.text(t.account.sync.lagging), findsNothing);
      expect(find.text(t.account.sync.turnOn), findsOneWidget);
    });

    testWidgets('is said plainly when it does not come, with a way to ask '
        'again instead of the paywall', (tester) async {
      cloud.refusal = const SyncException(SyncFailure.notPro);
      await show(tester, confirmPro: () async => false);

      expect(find.text(t.account.sync.lagging), findsOneWidget);
      expect(find.text(t.account.sync.retry), findsOneWidget);
      expect(find.text(t.account.sync.turnOn), findsNothing);
    });
  });

  testWidgets('leaving the screen with the app\'s coordinator does not read '
      'providers from a widget being torn down', (tester) async {
    final container = ProviderContainer(
      overrides: [
        syncCoordinatorProvider.overrideWithValue(
          SyncCoordinator(service: service, reload: () async {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpTestApp(tester, SyncCard(service: service), container: container);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());

    expect(tester.takeException(), isNull);
  });

  testWidgets('sync that lost Pro says it is paused and offers to renew', (
    tester,
  ) async {
    final coordinator = SyncCoordinator(service: service, reload: () async {});
    await tester.runAsync(() => service.setUp('correct horse'));
    cloud.refusal = const SyncException(SyncFailure.notPro);
    await tester.runAsync(() => coordinator.syncNow());
    await pumpTestApp(
      tester,
      SyncCard(service: service, coordinator: coordinator),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.account.sync.pausedBadge), findsOneWidget);
    expect(find.text(t.account.sync.renew), findsOneWidget);
    expect(find.text(t.account.sync.syncNow), findsNothing);
  });

  testWidgets('a forgotten passphrase can be got out of by starting over', (
    tester,
  ) async {
    final other = SyncService(
      cloud: cloud,
      vault: FakeSyncVault(),
      local: FakeSyncLocal(),
      uid: () => 'u1',
    );
    await tester.runAsync(() => other.setUp('correct horse'));
    await show(tester);

    await tester.tap(find.text(t.account.sync.forgot));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.account.sync.deleteAllConfirm));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(cloud.meta, isNull);
    expect(find.text(t.account.sync.turnOn), findsOneWidget);
  });

  testWidgets('turning on asks for the passphrase twice and refuses a '
      'mismatch', (tester) async {
    await show(tester);

    await tester.tap(find.text(t.account.sync.turnOn));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'short');
    await tester.tap(find.text(t.account.sync.turnOn).last);
    await tester.pumpAndSettle();
    expect(find.text(t.account.sync.tooShort), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).last, 'correct horse');
    await tester.tap(find.text(t.account.sync.turnOn).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'correct house');
    await tester.tap(find.text(t.account.sync.turnOn).last);
    await tester.pumpAndSettle();
    expect(find.text(t.account.sync.mismatch), findsOneWidget);

    await typeInDialog(tester, 'correct horse', t.account.sync.turnOn);

    expect(cloud.meta, isNotNull);
    expect(find.text(t.account.sync.syncNow), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('an account that syncs asks this device for the passphrase', (
    tester,
  ) async {
    final other = SyncService(
      cloud: cloud,
      vault: FakeSyncVault(),
      local: FakeSyncLocal(),
      uid: () => 'u1',
    );
    await tester.runAsync(() => other.setUp('correct horse'));

    await show(tester);

    expect(find.text(t.account.sync.locked), findsOneWidget);
    await tester.tap(find.text(t.account.sync.unlock));
    await tester.pumpAndSettle();
    await typeInDialog(tester, 'wrong horse', t.account.sync.unlock);
    expect(find.text(t.account.sync.failure.wrongPassphrase), findsOneWidget);
    expect(vault.keys, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
