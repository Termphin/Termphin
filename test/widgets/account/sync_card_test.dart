import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
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

  Future<void> show(WidgetTester tester) async {
    await pumpTestApp(tester, SyncCard(service: service));
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
    await other.setUp('correct horse');

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
