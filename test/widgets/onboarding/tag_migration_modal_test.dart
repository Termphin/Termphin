import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/app/tag_migration_service.dart';
import 'package:termphin/services/storage/group_storage.dart';
import 'package:termphin/services/storage/profile_storage.dart';
import 'package:termphin/services/storage/snippet_storage.dart';
import 'package:termphin/services/storage/ssh_key_storage.dart';
import 'package:termphin/widgets/onboarding/tag_migration_modal.dart';

import '../../support/fake_master_key_store.dart';
import '../../support/test_app.dart';

/// A legacy record: several tags, no group. Written straight to preferences so
/// the service reads it the way it reads a real one.
String _legacyProfile(String id, String name, List<String> tags) => jsonEncode({
  'id': id,
  'name': name,
  'host': 'example.com',
  'port': 22,
  'username': 'root',
  'authMethod': 'password',
  'tags': tags,
  'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProfileStorage profileStorage;
  late GroupStorage groupStorage;
  late TagMigrationService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TagMigrationService.debugForceOverride = false;
    profileStorage = ProfileStorage(cipher: cipherFixture());
    final snippetStorage = SnippetStorage();
    groupStorage = GroupStorage(
      profiles: profileStorage,
      keys: SshKeyStorage(cipher: cipherFixture()),
      snippets: snippetStorage,
    );
    service = TagMigrationService(
      profiles: profileStorage,
      snippets: snippetStorage,
      groups: groupStorage,
    );
  });

  Future<void> seed(List<String> rawProfiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('ssh_profiles', rawProfiles);
  }

  Future<void> pumpModal(WidgetTester tester) async {
    final plan = await service.detect();
    await pumpTestApp(tester, TagMigrationModal(plan: plan, service: service));
    await tester.pumpAndSettle();
  }

  testWidgets('every tag is ticked to start with', (tester) async {
    await seed([
      _legacyProfile('p1', 'Alpha', ['prod', 'eu']),
      _legacyProfile('p2', 'Beta', ['prod']),
    ]);

    await pumpModal(tester);

    expect(find.text('prod'), findsOneWidget);
    expect(find.text('eu'), findsOneWidget);
    for (final box in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
      expect(box.value, isTrue);
    }
    expect(find.text('Create groups'), findsOneWidget);
  });

  testWidgets('unticking everything turns the commit into the skip path', (
    tester,
  ) async {
    await seed([
      _legacyProfile('p1', 'Alpha', ['prod']),
    ]);

    await pumpModal(tester);
    expect(find.text('Create groups'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('Create groups'), findsNothing);
    expect(find.text('Start fresh'), findsOneWidget);
  });

  testWidgets('a record whose first tag was dropped joins its first kept one', (
    tester,
  ) async {
    await seed([
      _legacyProfile('p1', 'Alpha', ['eu', 'prod']),
      _legacyProfile('p2', 'Beta', ['prod']),
      _legacyProfile('p3', 'Gamma', ['prod']),
    ]);

    await pumpModal(tester);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'eu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create groups'));
    await tester.pumpAndSettle();

    final groups = (await groupStorage.loadGroups()).map((g) => g.name);
    expect(groups, contains('prod'));
    expect(groups, isNot(contains('eu')));

    final profiles = await profileStorage.loadProfiles();
    expect(profiles.firstWhere((p) => p.id == 'p1').group, 'prod');
  });
}
