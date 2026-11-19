import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/app/debug_interstitials.dart';
import 'package:termphin/services/app/whats_new_service.dart';

const _a = ReleaseHighlight(
  id: 'a',
  version: '1.0.0',
  title: 'First',
  body: 'b',
);
const _b = ReleaseHighlight(
  id: 'b',
  version: '1.2.0',
  title: 'Later one',
  body: 'b',
);
const _c = ReleaseHighlight(
  id: 'c',
  version: '1.2.0',
  title: 'Later two',
  body: 'b',
);
const _unreleased = ReleaseHighlight(
  id: 'unreleased_feature',
  version: 'Unreleased',
  title: 'In Progress',
  body: 'b',
);
const _ahead = ReleaseHighlight(
  id: 'ahead_feature',
  version: '2.0.0',
  title: 'Future Feature',
  body: 'b',
);

const _highlights = [_a, _b, _c];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = WhatsNewService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.debugSetHighlights(_highlights);
    service.debugSetForcing(false);
  });

  tearDown(() {
    service.debugSetHighlights(null);
    service.debugSetForcing(null);
  });

  test('a fresh install seeds every released id and shows nothing', () async {
    expect(await service.pendingSince('1.2.0'), isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(kSeenWhatsNewIdsPrefsKey)?.toSet(), {
      'a',
      'b',
      'c',
    });
  });

  test(
    'installing, then updating, still shows nothing for the same ids',
    () async {
      await service.pendingSince('1.2.0');
      expect(await service.pendingSince('1.2.0'), isEmpty);
    },
  );

  test('an update shows only the ids that arrived with it', () async {
    service.debugSetHighlights(const [_a]);
    await service.pendingSince('1.0.0');

    service.debugSetHighlights(_highlights);
    final pending = await service.pendingSince('1.2.0');

    expect(pending.map((h) => h.id), ['b', 'c']);
  });

  test('a seen highlight never comes back', () async {
    service.debugSetHighlights(const [_a]);
    await service.pendingSince('1.0.0');
    service.debugSetHighlights(_highlights);

    final pending = await service.pendingSince('1.2.0');
    await service.markSeen(pending);

    expect(await service.pendingSince('1.2.0'), isEmpty);
  });

  test('marking one of two leaves the other pending', () async {
    service.debugSetHighlights(const [_a]);
    await service.pendingSince('1.0.0');
    service.debugSetHighlights(_highlights);

    await service.markSeen(const [_b]);

    expect((await service.pendingSince('1.2.0')).map((h) => h.id), ['c']);
  });

  test(
    'highlights above the running version are held back, not seeded',
    () async {
      await service.pendingSince('1.0.0');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(kSeenWhatsNewIdsPrefsKey), ['a']);

      expect((await service.pendingSince('1.2.0')).map((h) => h.id), [
        'b',
        'c',
      ]);
    },
  );

  test('pending highlights page forward in release order', () async {
    SharedPreferences.setMockInitialValues({
      kSeenWhatsNewIdsPrefsKey: <String>[],
    });

    final pending = await service.pendingSince('1.2.0');

    expect(pending.map((h) => h.version), ['1.0.0', '1.2.0', '1.2.0']);
  });

  test('a release with nothing new to say shows nothing', () async {
    SharedPreferences.setMockInitialValues({
      kSeenWhatsNewIdsPrefsKey: ['a', 'b', 'c'],
    });

    expect(await service.pendingSince('1.2.0'), isEmpty);
  });

  test('the bundled asset fills in every field', () async {
    service.debugSetHighlights(null);
    SharedPreferences.setMockInitialValues({
      kSeenWhatsNewIdsPrefsKey: <String>[],
    });

    final all = await service.pendingSince('999.0.0');

    expect(all, isNotEmpty);
    for (final highlight in all) {
      expect(highlight.id, isNotEmpty);
      expect(highlight.title, isNotEmpty);
      expect(highlight.body, isNotEmpty);
    }
  });

  group('an id repeated under two versions', () {
    const older = ReleaseHighlight(
      id: 'newfeature',
      version: '1.0.0',
      title: 'Old wording',
      body: 'b',
    );
    const newer = ReleaseHighlight(
      id: 'newfeature',
      version: '1.1.0',
      title: 'New wording',
      body: 'b',
    );

    setUp(() => service.debugSetHighlights(const [older, newer]));

    test('is one page, carrying the newest wording', () async {
      SharedPreferences.setMockInitialValues({
        kSeenWhatsNewIdsPrefsKey: <String>[],
      });

      final pending = await service.pendingSince('1.1.0');

      expect(pending, hasLength(1));
      expect(pending.single.title, 'New wording');
    });

    test('does not come back after the update that reworded it', () async {
      SharedPreferences.setMockInitialValues({
        kSeenWhatsNewIdsPrefsKey: <String>[],
      });
      final first = await service.pendingSince('1.0.0');
      expect(first.single.title, 'Old wording');
      await service.markSeen(first);

      expect(await service.pendingSince('1.1.0'), isEmpty);
    });

    test('shows the older wording while the build is still on 1.0.0', () async {
      SharedPreferences.setMockInitialValues({
        kSeenWhatsNewIdsPrefsKey: <String>[],
      });

      final pending = await service.pendingSince('1.0.0');

      expect(pending, hasLength(1));
      expect(pending.single.title, 'Old wording');
    });

    test('a fresh install seeds the id once and stays quiet', () async {
      expect(await service.pendingSince('1.1.0'), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(kSeenWhatsNewIdsPrefsKey), ['newfeature']);
      expect(await service.pendingSince('1.1.0'), isEmpty);
    });
  });

  group('when forcing', () {
    setUp(() => service.debugSetForcing(true));

    test(
      'returns highlights even when every id is already in the seen set',
      () async {
        SharedPreferences.setMockInitialValues({
          kSeenWhatsNewIdsPrefsKey: ['a', 'b', 'c'],
        });

        final pending = await service.pendingSince('1.2.0');

        expect(pending.map((h) => h.id), ['a', 'b', 'c']);
      },
    );

    test(
      'skips first-run seeding on a fresh install and returns highlights',
      () async {
        SharedPreferences.setMockInitialValues({});

        final pending = await service.pendingSince('1.2.0');

        expect(pending.map((h) => h.id), ['a', 'b', 'c']);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(kSeenWhatsNewIdsPrefsKey), isNull);
      },
    );

    test(
      'returns an entry whose version is not a released dotted number, and does not throw',
      () async {
        service.debugSetHighlights([_unreleased, ..._highlights]);

        final pending = await service.pendingSince('1.2.0');

        expect(pending.map((h) => h.id), ['a', 'b', 'c', 'unreleased_feature']);
        expect(pending.last.version, 'Unreleased');
      },
    );

    test(
      'returns an entry whose version is ahead of the current build',
      () async {
        service.debugSetHighlights([..._highlights, _ahead]);

        final pending = await service.pendingSince('1.2.0');

        expect(pending.map((h) => h.id), ['a', 'b', 'c', 'ahead_feature']);
      },
    );

    test('markSeen leaves the stored seen set unchanged', () async {
      SharedPreferences.setMockInitialValues({
        kSeenWhatsNewIdsPrefsKey: ['a'],
      });

      await service.markSeen(const [_b, _c]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(kSeenWhatsNewIdsPrefsKey), ['a']);
    });

    test(
      'returns highlights on every call without being muted by markSeen',
      () async {
        final first = await service.pendingSince('1.2.0');
        expect(first, isNotEmpty);
        await service.markSeen(first);

        final second = await service.pendingSince('1.2.0');
        expect(second.map((h) => h.id), first.map((h) => h.id));
      },
    );

    test('forced path is reachable via WhatsNewService.forTesting', () async {
      final testService = WhatsNewService.forTesting(forcing: true);
      testService.debugSetHighlights(_highlights);
      SharedPreferences.setMockInitialValues({
        kSeenWhatsNewIdsPrefsKey: ['a', 'b', 'c'],
      });

      final pending = await testService.pendingSince('1.2.0');

      expect(pending.map((h) => h.id), ['a', 'b', 'c']);
    });

    test(
      'defaults to reading kForceInterstitials when override is null',
      () async {
        service.debugSetForcing(null);
        SharedPreferences.setMockInitialValues({
          kSeenWhatsNewIdsPrefsKey: ['a', 'b', 'c'],
        });

        final pending = await service.pendingSince('1.2.0');

        expect(
          pending.map((h) => h.id),
          kForceInterstitials ? ['a', 'b', 'c'] : isEmpty,
        );
      },
    );
  });

  group('with forcing off', () {
    setUp(() => service.debugSetForcing(false));

    test('returns nothing when every id is already in the seen set', () async {
      SharedPreferences.setMockInitialValues({
        kSeenWhatsNewIdsPrefsKey: ['a', 'b', 'c'],
      });

      expect(await service.pendingSince('1.2.0'), isEmpty);
    });

    test(
      'omits an entry whose version is not a released dotted number and does not throw',
      () async {
        SharedPreferences.setMockInitialValues({
          kSeenWhatsNewIdsPrefsKey: <String>[],
        });
        service.debugSetHighlights([_unreleased, ..._highlights]);

        final pending = await service.pendingSince('1.2.0');

        expect(pending.map((h) => h.id), ['a', 'b', 'c']);
      },
    );

    test(
      'omits an entry whose version is ahead of the current build',
      () async {
        SharedPreferences.setMockInitialValues({
          kSeenWhatsNewIdsPrefsKey: <String>[],
        });
        service.debugSetHighlights([..._highlights, _ahead]);

        final pending = await service.pendingSince('1.2.0');

        expect(pending.map((h) => h.id), ['a', 'b', 'c']);
      },
    );

    test('markSeen records highlights into the stored seen set', () async {
      SharedPreferences.setMockInitialValues({
        kSeenWhatsNewIdsPrefsKey: ['a'],
      });

      await service.markSeen(const [_b]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(kSeenWhatsNewIdsPrefsKey)?.toSet(), {
        'a',
        'b',
      });
    });
  });

  test('an aspect is width over height, and nonsense is ignored', () {
    expect(parseAspect('9:16'), 9 / 16);
    expect(parseAspect(' 16 : 9 '), 16 / 9);
    expect(parseAspect('16x9'), isNull);
    expect(parseAspect('0:9'), isNull);
    expect(parseAspect(null), isNull);
  });

  group('highlight by id', () {
    late WhatsNewService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = WhatsNewService.forTesting(forcing: false)
        ..debugSetHighlights(const [
          _a,
          ReleaseHighlight(
            id: 'a',
            version: '1.1.0',
            title: 'First, reworded',
            body: 'b',
          ),
          _unreleased,
        ]);
    });

    test('is the newest wording, released or not', () async {
      expect((await service.highlight('a'))?.title, 'First, reworded');
      expect(
        (await service.highlight('unreleased_feature'))?.title,
        'In Progress',
      );
      expect(await service.highlight('nope'), isNull);
    });

    test('is not recorded as seen', () async {
      await service.highlight('a');
      final preferences = await SharedPreferences.getInstance();

      expect(preferences.getStringList(kSeenWhatsNewIdsPrefsKey), isNull);
    });
  });

  test('a page that only explains is never announced', () async {
    SharedPreferences.setMockInitialValues({
      kSeenWhatsNewIdsPrefsKey: <String>[],
    });
    final service = WhatsNewService.forTesting(forcing: false)
      ..debugSetHighlights(const [
        _a,
        ReleaseHighlight(
          id: 'old-feature',
          version: '1.0.0',
          title: 'Explained only',
          body: 'b',
          announce: false,
        ),
      ]);

    final pending = await service.pendingSince('1.0.0');

    expect(pending.map((h) => h.id), ['a']);
    expect((await service.highlight('old-feature'))?.title, 'Explained only');
  });
}
