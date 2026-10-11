import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/toolbar_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  test('an install with a layout but no profiles keeps that layout', () async {
    SharedPreferences.setMockInitialValues({
      kToolbarOrderPrefsKey: ['esc', 'tab'],
      kToolbarColumnsPrefsKey: 4,
      kToolbarRowsPrefsKey: 1,
      kToolbarPagesPrefsKey: 1,
    });
    SharedPreferences.resetStatic();
    await loadAppSettings();

    final profiles = toolbarSettings.profiles.value;
    expect(profiles.profiles, hasLength(1));
    expect(profiles.active.id, kDefaultToolbarProfileId);
    expect(profiles.active.layout.order.take(2), ['esc', 'tab']);
    expect(profiles.active.layout.columns, 4);
  });

  test('editing the layout writes through to the profile in use', () async {
    await saveToolbarLayout(ToolbarLayout.defaults.copyWith(buttonHeight: 44));

    expect(toolbarSettings.profiles.value.active.layout.buttonHeight, 44);
  });

  test('switching profiles is what changes the live layout', () async {
    final other = ToolbarProfile(
      id: 'other',
      name: 'Vim',
      layout: ToolbarLayout.blank.copyWith(buttonHeight: 30),
    );
    await saveToolbarProfiles(
      toolbarSettings.profiles.value.added(other, activate: false),
    );
    expect(toolbarSettings.layout.value.buttonHeight, isNot(30));

    await activateToolbarProfile('other');

    expect(toolbarSettings.profiles.value.activeId, 'other');
    expect(toolbarSettings.layout.value.buttonHeight, 30);
    expect(
      toolbarSettings.layout.value.order.where((id) => id.isNotEmpty),
      isEmpty,
    );
  });

  test('an edit lands on the profile that is in use, not the others', () async {
    final other = ToolbarProfile(
      id: 'other',
      name: 'Vim',
      layout: ToolbarLayout.blank,
    );
    await saveToolbarProfiles(
      toolbarSettings.profiles.value.added(other, activate: false),
    );

    await saveToolbarLayout(ToolbarLayout.defaults.copyWith(buttonHeight: 41));

    final profiles = toolbarSettings.profiles.value;
    expect(profiles.active.layout.buttonHeight, 41);
    expect(
      profiles.profiles.firstWhere((p) => p.id == 'other').layout.buttonHeight,
      isNot(41),
    );
  });

  test('the last profile cannot be deleted', () {
    final only = toolbarSettings.profiles.value;
    expect(only.profiles, hasLength(1));
    expect(only.removed(only.activeId).profiles, hasLength(1));
  });

  test('deleting the profile in use hands the toolbar to another', () {
    final profiles = ToolbarProfiles(
      profiles: [
        ToolbarProfile(id: 'a', name: 'A', layout: ToolbarLayout.defaults),
        ToolbarProfile(id: 'b', name: 'B', layout: ToolbarLayout.blank),
      ],
      activeId: 'b',
    );

    final next = profiles.removed('b');
    expect(next.profiles.map((p) => p.id), ['a']);
    expect(next.activeId, 'a');
  });

  test('an active id naming nothing resolves to a profile that exists', () {
    final profiles = ToolbarProfiles(
      profiles: [
        ToolbarProfile(id: 'a', name: 'A', layout: ToolbarLayout.defaults),
      ],
      activeId: 'gone',
    );
    expect(profiles.activeId, 'a');
    expect(profiles.active.id, 'a');
  });

  test('one unreadable entry does not cost the others', () async {
    SharedPreferences.setMockInitialValues({
      kToolbarProfilesPrefsKey: [
        'not json at all',
        '{"id":"b","name":"Logs","order":[],"columns":6,"rows":1,"pages":1}',
      ],
      kToolbarActiveProfilePrefsKey: 'b',
    });
    SharedPreferences.resetStatic();
    await loadAppSettings();

    final profiles = toolbarSettings.profiles.value;
    expect(profiles.profiles.map((p) => p.id), ['b']);
    expect(profiles.activeId, 'b');
  });

  test('an unreadable store falls back to the stored layout', () async {
    SharedPreferences.setMockInitialValues({
      kToolbarProfilesPrefsKey: ['not json at all'],
      kToolbarOrderPrefsKey: ['esc', 'tab'],
      kToolbarColumnsPrefsKey: 4,
      kToolbarRowsPrefsKey: 1,
      kToolbarPagesPrefsKey: 1,
    });
    SharedPreferences.resetStatic();
    await loadAppSettings();

    final profiles = toolbarSettings.profiles.value;
    expect(profiles.profiles, hasLength(1));
    expect(profiles.active.id, kDefaultToolbarProfileId);
    expect(profiles.active.layout.order.take(2), ['esc', 'tab']);
    expect(profiles.active.layout.columns, 4);
  });

  test('profiles survive being written and read back', () async {
    await saveToolbarProfiles(
      ToolbarProfiles(
        profiles: [
          ToolbarProfile(id: 'a', name: 'A', layout: ToolbarLayout.defaults),
          ToolbarProfile(
            id: 'b',
            name: 'Logs',
            layout: ToolbarLayout.blank.copyWith(columns: 6, rows: 1, pages: 1),
          ),
        ],
        activeId: 'b',
      ),
    );

    await toolbarSettings.profiles.load();

    final read = toolbarSettings.profiles.value;
    expect(read.profiles.map((p) => p.name), ['A', 'Logs']);
    expect(read.activeId, 'b');
    expect(read.active.layout.columns, 6);
  });
}
