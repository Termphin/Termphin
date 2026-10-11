import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/backup/export_service.dart';
import 'package:termphin/widgets/backup/backup_import_options.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  ImportPreview previewOf({
    List<BackupItem> profiles = const [],
    bool hasTerminalSettings = false,
  }) => ImportPreview(
    version: 3,
    exportedAt: DateTime.utc(2026, 5, 6, 7, 8),
    profiles: profiles,
    sshKeys: const [],
    snippets: const [],
    knownHosts: const [],
    hasTerminalSettings: hasTerminalSettings,
    hasAppPreferences: false,
    wasEncrypted: false,
    payload: const {},
  );

  /// The panel, plus the last thing it reported - what the screen's pinned
  /// Import button reads.
  Future<ValueGetter<ImportOptions?>> pumpPanel(
    WidgetTester tester,
    ImportPreview preview,
  ) async {
    ImportOptions? reported;
    await pumpTestApp(
      tester,
      ImportOptionsPanel(
        preview: preview,
        onChanged: (options) => reported = options,
      ),
    );
    await tester.pumpAndSettle();
    return () => reported;
  }

  testWidgets('lists what is in the file rather than a bare count', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      previewOf(
        profiles: const [
          BackupItem(
            id: 'a',
            label: 'Production',
            detail: 'deploy@example.com',
          ),
          BackupItem(id: 'b', label: 'Staging', detail: 'deploy@stage'),
        ],
      ),
    );

    await tester.tap(find.text(t.exportScreen.showItems));
    await tester.pumpAndSettle();

    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Staging'), findsOneWidget);
  });

  testWidgets('reports its opening selection without being touched', (
    tester,
  ) async {
    final options = await pumpPanel(
      tester,
      previewOf(
        profiles: const [BackupItem(id: 'a', label: 'Production')],
      ),
    );

    expect(options()?.mergeProfiles, isTrue);
    expect(options()?.profileIds, {'a'});
  });

  testWidgets('carries only the entries left ticked', (tester) async {
    final options = await pumpPanel(
      tester,
      previewOf(
        profiles: const [
          BackupItem(id: 'a', label: 'Production'),
          BackupItem(id: 'b', label: 'Staging'),
        ],
      ),
    );

    await tester.tap(find.text(t.exportScreen.showItems));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staging'));
    await tester.pumpAndSettle();

    expect(options()?.profileIds, {'a'});
  });

  testWidgets('asks what to do only when something would clash', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      previewOf(
        profiles: const [BackupItem(id: 'a', label: 'Production')],
      ),
    );

    expect(find.text(t.exportScreen.conflictsSkip), findsNothing);
  });

  testWidgets('offers keep-mine and overwrite for entries already here', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      previewOf(
        profiles: const [
          BackupItem(id: 'a', label: 'Production', exists: true),
        ],
      ),
    );

    expect(find.text(t.exportScreen.conflictsSkip), findsOneWidget);
    expect(find.text(t.exportScreen.conflictsReplace), findsOneWidget);
    expect(find.text(t.exportScreen.alreadyHere), findsNothing);

    await tester.tap(find.text(t.exportScreen.showItems));
    await tester.pumpAndSettle();
    expect(find.text(t.exportScreen.alreadyHere), findsOneWidget);
  });

  testWidgets('overwrite is a deliberate pick, not the default', (
    tester,
  ) async {
    final options = await pumpPanel(
      tester,
      previewOf(
        profiles: const [
          BackupItem(id: 'a', label: 'Production', exists: true),
        ],
      ),
    );

    expect(options()?.conflicts, ImportConflicts.skip);

    await tester.tap(find.text(t.exportScreen.conflictsReplace));
    await tester.pumpAndSettle();
    expect(options()?.conflicts, ImportConflicts.replace);
  });

  testWidgets('reports nothing once every section is off', (tester) async {
    final options = await pumpPanel(
      tester,
      previewOf(
        profiles: const [BackupItem(id: 'a', label: 'Production')],
        hasTerminalSettings: true,
      ),
    );

    for (final title in [
      t.exportScreen.sectionProfiles,
      t.exportScreen.includeTerminalSettings,
    ]) {
      await tester.tap(
        find
            .descendant(
              of: find.ancestor(
                of: find.text(title),
                matching: find.byType(SwitchListTile),
              ),
              matching: find.byType(Switch),
            )
            .first,
      );
      await tester.pumpAndSettle();
    }

    expect(options(), isNull);
  });
}
