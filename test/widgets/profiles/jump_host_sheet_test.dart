import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/services/app/identity_anonymizer.dart';
import 'package:termphin/services/settings/anonymize_setting.dart';
import 'package:termphin/widgets/profiles/jump_host_sheet.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  late List<String?> picked;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await anonymizeSetting.set(false);
    picked = [];
  });

  tearDown(() => anonymizeSetting.set(false));

  Future<void> pump(
    WidgetTester tester,
    List<SshProfile> candidates, {
    String? selectedId,
  }) async {
    final container = ProviderContainer.test(
      overrides: [
        groupStorageProvider.overrideWithValue(
          FakeGroupStorage(
            initialGroups: const [ProfileGroup(name: 'General')],
          ),
        ),
      ],
    );
    await container.read(profileGroupsProvider.notifier).loadGroups();

    await pumpTestApp(
      tester,
      Scaffold(
        body: JumpHostSheetContent(
          candidates: candidates,
          group: 'General',
          selectedId: selectedId,
          onPick: picked.add,
        ),
      ),
      container: container,
    );
    await tester.pumpAndSettle();
  }

  Finder checkIn(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byIcon(PhosphorIconsRegular.checkCircle),
  );

  testWidgets('marks the current jump host and nothing else', (tester) async {
    await pump(tester, [
      profileFixture(id: 'a', name: 'Alpha'),
      profileFixture(id: 'b', name: 'Beta'),
    ], selectedId: 'b');

    expect(checkIn('jumpHostCandidate:b'), findsOneWidget);
    expect(checkIn('jumpHostCandidate:a'), findsNothing);
    expect(checkIn('jumpHostDirect'), findsNothing);
  });

  testWidgets('marks the direct connection when nothing is picked', (
    tester,
  ) async {
    await pump(tester, [profileFixture(id: 'a', name: 'Alpha')]);

    expect(checkIn('jumpHostDirect'), findsOneWidget);
    expect(checkIn('jumpHostCandidate:a'), findsNothing);
  });

  testWidgets('hands back the tapped machine, or null for direct', (
    tester,
  ) async {
    await pump(tester, [
      profileFixture(id: 'a', name: 'Alpha'),
    ], selectedId: 'a');

    await tester.tap(find.text('Alpha'));
    await tester.tap(find.text(t.profileForm.jumpHostNone));

    expect(picked, ['a', null]);
  });

  testWidgets('shows placeholders instead of the real identity', (
    tester,
  ) async {
    await anonymizeSetting.set(true);
    await pump(tester, [
      profileFixture(
        id: 'a',
        name: 'Alpha',
        username: 'root',
        host: 'secret.example.com',
      ),
    ]);

    expect(find.text('Alpha'), findsNothing);
    expect(find.textContaining('secret.example.com'), findsNothing);
    expect(find.text(IdentityAnonymizer.name('a')), findsOneWidget);
    expect(find.textContaining(IdentityAnonymizer.host('a')), findsOneWidget);
  });
}
