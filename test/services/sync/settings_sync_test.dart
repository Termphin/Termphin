import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/backup/app_preferences_backup.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/services/sync/settings_sync.dart';
import 'package:termphin/services/sync/sync_engine.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await terminalSettings.load();
  });

  test('every preference the backup carries is either synced or kept on '
      'the device, never both, never neither', () async {
    final exported = {
      for (final key in (await exportTerminalSettings()).keys) 'terminal.$key',
      for (final key in (await exportAppPreferences()).keys) 'app.$key',
    };
    final synced = kSyncedSettingGroups.values.expand((keys) => keys).toList();

    expect(synced.toSet().length, synced.length, reason: 'a key in two groups');
    expect(synced.toSet().intersection(kDeviceSettings), isEmpty);
    expect(
      exported.difference({...synced, ...kDeviceSettings}),
      isEmpty,
      reason: 'decide whether these follow the account or stay here',
    );
    expect({...synced, ...kDeviceSettings}.difference(exported), isEmpty);
  });

  test('a synced preference reaches another device; a device-only one does '
      'not travel', () async {
    final sync = SettingsSync();
    await terminalSettings.scheme.set('dracula');
    await terminalSettings.fontSize.set(19);

    final records = await sync.readAll();
    final scheme = records.singleWhere((r) => r.id == 'terminal.scheme');
    expect(scheme.data, {'terminal.schemeId': 'dracula'});
    expect(
      records.expand((r) => r.data.keys),
      isNot(contains('terminal.fontSize')),
    );

    SharedPreferences.setMockInitialValues({});
    await terminalSettings.load();
    await SettingsSync().upsert(scheme);

    expect(terminalSettings.scheme.value, 'dracula');
    expect(terminalSettings.fontSize.value, isNot(19));
  });

  test('a preference unchanged here keeps its time, so it does not win '
      'against a change made elsewhere', () async {
    final sync = SettingsSync();
    final first = await sync.readAll();
    final again = await sync.readAll();
    final at = {for (final r in first) r.id: r.updatedAt};

    for (final record in again) {
      expect(record.updatedAt, at[record.id], reason: record.id);
    }
    await terminalSettings.cursorBlink.set(!terminalSettings.cursorBlink.value);
    final changed = (await sync.readAll()).singleWhere(
      (r) => r.id == 'terminal.cursor',
    );
    expect(changed.updatedAt.isAfter(at['terminal.cursor']!), isTrue);
  });

  test('a value the importer normalises keeps the remote time on the next '
      'read, so two versions do not trade it back and forth', () async {
    final remote = DateTime.utc(2020, 1, 2);
    final sync = SettingsSync();
    await sync.upsert(
      SyncRecord(
        kind: kSettingKind,
        id: 'app.dock',
        data: const {
          'app.dockOrder': ['noSuchAction'],
          'app.dockHidden': <String>[],
          'app.dockEnabled': true,
        },
        updatedAt: remote,
      ),
    );

    final dock = (await sync.readAll()).singleWhere((r) => r.id == 'app.dock');
    expect(dock.data['app.dockOrder'], isNot(['noSuchAction']));
    expect(dock.updatedAt, remote);
  });
}
