import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/screens/settings/phin_server_notes_screen.dart';
import 'package:termphin/screens/settings/phin_settings_screen.dart';
import 'package:termphin/services/assistant/assistant_memory.dart';
import 'package:termphin/services/pro/pro_service.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/secure_storage_channel.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync().assistant;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    assistantMemory.forgetCache();
    ProService.instance.active.value = true;
  });

  tearDown(() => ProService.instance.active.value = false);

  Future<void> show(WidgetTester tester) async {
    await tester.runAsync(() async {
      await assistantMemory.add('web', 'The shop runs as shop-api.');
      await assistantMemory.add('web', 'nginx logs are in /var/log/nginx.');
      await assistantMemory.add('nas', 'Backups run nightly with restic.');
    });
    final container = ProviderContainer.test(
      overrides: [
        profileStorageProvider.overrideWithValue(
          FakeProfileStorage([
            profileFixture(id: 'web', name: 'Web server'),
            profileFixture(id: 'nas', name: 'Home NAS'),
          ]),
        ),
      ],
    );
    await tester.runAsync(
      () => container.read(profilesProvider.notifier).loadProfiles(),
    );
    await pumpTestApp(tester, const PhinSettingsScreen(), container: container);
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('lists each server with how many notes it has, not the notes', (
    tester,
  ) async {
    await show(tester);

    expect(find.text('Web server'), findsOneWidget);
    expect(find.text(t.knowsNotes(n: 2)), findsOneWidget);
    expect(find.text(t.knowsNotes(n: 1)), findsOneWidget);
    expect(find.text('The shop runs as shop-api.'), findsNothing);
  });

  testWidgets('a server opens its notes, each one to remove', (tester) async {
    await show(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('phinKnows-web')));
    await tester.tap(find.byKey(const ValueKey('phinKnows-web')));
    await tester.pumpAndSettle();
    expect(find.byType(PhinServerNotesScreen), findsOneWidget);
    expect(find.text('The shop runs as shop-api.'), findsOneWidget);

    await tester.tap(find.byTooltip(t.removeNote).first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('The shop runs as shop-api.'), findsNothing);
    expect(await tester.runAsync(() => assistantMemory.notesFor('web')), [
      'nginx logs are in /var/log/nginx.',
    ]);
  });

  testWidgets('forgetting a server asks, then goes back to the list', (
    tester,
  ) async {
    await show(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('phinKnows-nas')));
    await tester.tap(find.byKey(const ValueKey('phinKnows-nas')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('phinForgetServer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.forget).last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PhinServerNotesScreen), findsNothing);
    expect(find.text('Home NAS'), findsNothing);
    expect(
      await tester.runAsync(() => assistantMemory.notesFor('nas')),
      isEmpty,
    );
  });
}
