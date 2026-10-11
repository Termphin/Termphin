import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/app/release_notes_service.dart';
import 'package:termphin/services/app/version_compare.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh install is marked seen and shown nothing', () async {
    final pending = await ReleaseNotesService.instance.pendingSince('1.0.0');

    expect(pending, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kLastSeenReleaseNotesVersionPrefsKey), '1.0.0');
  });

  test(
    'an update returns only versions newer than the one last seen',
    () async {
      SharedPreferences.setMockInitialValues({
        kLastSeenReleaseNotesVersionPrefsKey: '0.9.0',
      });

      final pending = await ReleaseNotesService.instance.pendingSince('1.0.0');

      expect(pending.map((e) => e.version), ['1.0.0']);
    },
  );

  test(
    'nothing is pending when the current version was already seen',
    () async {
      SharedPreferences.setMockInitialValues({
        kLastSeenReleaseNotesVersionPrefsKey: '1.0.0',
      });

      expect(await ReleaseNotesService.instance.pendingSince('1.0.0'), isEmpty);
    },
  );

  test(
    'a version newer than the running build is not announced early',
    () async {
      SharedPreferences.setMockInitialValues({
        kLastSeenReleaseNotesVersionPrefsKey: '0.1.0',
      });

      expect(await ReleaseNotesService.instance.pendingSince('0.2.0'), isEmpty);
    },
  );

  test('markSeen records the version', () async {
    await ReleaseNotesService.instance.markSeen('2.3.4');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kLastSeenReleaseNotesVersionPrefsKey), '2.3.4');
  });

  test('an Unreleased entry is not in the history', () async {
    final versions = (await ReleaseNotesService.instance.allEntries())
        .map((e) => e.version)
        .toList();

    expect(versions, isNot(contains('Unreleased')));
    for (final version in versions) {
      expect(isReleasedVersion(version), isTrue, reason: version);
    }
  });

  test('the bundled asset parses into ordered, non-empty categories', () async {
    final entries = await ReleaseNotesService.instance.allEntries();

    expect(entries, isNotEmpty);
    for (final entry in entries) {
      expect(entry.version, isNotEmpty);
      expect(entry.date, isNotEmpty);
      for (final category in entry.categories) {
        expect(category.items, isNotEmpty);
      }
    }
  });

  test('allEntries is sorted newest first', () async {
    final versions = (await ReleaseNotesService.instance.allEntries())
        .map((e) => e.version)
        .toList();

    final descending = [...versions]
      ..sort((a, b) {
        int compare(String x, String y) {
          final xs = x.split('.').map(int.parse).toList();
          final ys = y.split('.').map(int.parse).toList();
          for (var i = 0; i < xs.length || i < ys.length; i++) {
            final xv = i < xs.length ? xs[i] : 0;
            final yv = i < ys.length ? ys[i] : 0;
            if (xv != yv) return xv.compareTo(yv);
          }
          return 0;
        }

        return compare(b, a);
      });
    expect(versions, descending);
  });
}
