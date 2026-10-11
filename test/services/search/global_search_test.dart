import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/active_session.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/snippet.dart';
import 'package:termphin/models/ssh_key.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/search/global_search.dart';

import '../../support/fixtures.dart';

void main() {
  final web = profileFixture(
    id: 'web',
    name: 'web-1',
    host: '10.0.0.4',
    username: 'root',
    group: 'Production',
    lastConnectedAt: DateTime.utc(2026, 9, 1),
  );
  final db = profileFixture(
    id: 'db',
    name: 'database',
    host: 'db.internal',
    username: 'postgres',
    group: 'Production',
    lastConnectedAt: DateTime.utc(2026, 9, 3),
  );
  final pi = profileFixture(
    id: 'pi',
    name: 'raspberry',
    host: '192.168.1.20',
    username: 'pi',
    group: 'gone-group',
    lastConnectedAt: DateTime.utc(2026, 9, 2),
  );
  const groups = [
    ProfileGroup(name: 'General'),
    ProfileGroup(name: 'Production'),
  ];
  final restart = snippetFixture(
    id: 's1',
    name: 'Restart nginx',
    command: 'sudo systemctl restart nginx',
    group: 'Production',
  );
  final laptop = sshKeyFixture(id: 'k1', name: 'laptop', group: 'General');
  final rsa = sshKeyFixture(
    id: 'k2',
    name: 'ci',
    keyType: SshKeyType.rsa4096,
    group: 'Production',
  );

  ActiveSessionView session(
    SshProfile profile, {
    String? mux,
    bool dropped = false,
    bool isRun = false,
  }) => ActiveSessionView(
    id: 'tab-${profile.id}-$mux',
    profile: profile,
    connectedAt: DateTime.utc(2026, 9, 1),
    muxName: mux,
    isRun: isRun,
  )..dropped = dropped;

  GlobalSearchResults search(
    String query, {
    String? scope,
    List<ActiveSessionView> sessions = const [],
    List<Snippet> snippets = const [],
    List<SshKey> keys = const [],
  }) => globalSearch(
    query: query,
    profiles: [web, db, pi],
    groups: groups,
    sessions: sessions,
    snippets: snippets,
    keys: keys,
    generalLabel: 'Ogólne',
    scope: scope,
  );

  group('machines', () {
    test('match by name, address, username and user@host', () {
      expect(search('web').machines, [web]);
      expect(search('10.0.0').machines, [web]);
      expect(search('postgres').machines, [db]);
      expect(search('pi@192').machines, [pi]);
    });

    test('match by the group they sit in, case-insensitively', () {
      expect(search('PRODUCTION').machines, unorderedEquals([web, db]));
    });

    test('a machine in an unknown group counts as General, by either name', () {
      expect(search('general').machines, [pi]);
      expect(search('ogólne').machines, [pi]);
    });

    test('every word has to match somewhere', () {
      expect(search('production root').machines, [web]);
      expect(search('production pi').machines, isEmpty);
    });

    test(
      'a name starting with the word comes before one merely holding it',
      () {
        final results = globalSearch(
          query: 'data',
          profiles: [
            profileFixture(id: 'a', name: 'bigdata', host: 'x'),
            profileFixture(id: 'b', name: 'database', host: 'y'),
          ],
          groups: groups,
          sessions: const [],
          snippets: const [],
          keys: const [],
          generalLabel: 'General',
        );
        expect(results.machines.map((p) => p.id), ['b', 'a']);
      },
    );
  });

  group('sessions', () {
    test('match by their own name and by their machine', () {
      final deploy = session(web, mux: 'deploy');
      final other = session(db, mux: 'logs');
      expect(search('deploy', sessions: [deploy, other]).sessions, [deploy]);
      expect(search('postgres', sessions: [deploy, other]).sessions, [other]);
    });

    test('a snippet run is never a session', () {
      final run = session(web, mux: 'deploy', isRun: true);
      expect(search('deploy', sessions: [run]).sessions, isEmpty);
    });

    test('a detached session is found', () {
      final detached = session(web, mux: 'build', dropped: true);
      expect(search('build', sessions: [detached]).sessions, [detached]);
    });
  });

  group('groups, snippets and keys', () {
    test('a group says what it holds', () {
      final hit = search(
        'prod',
        snippets: [restart],
        keys: [laptop, rsa],
      ).groups.single;
      expect(hit.group.name, 'Production');
      expect((hit.machines, hit.snippets, hit.keys), (2, 1, 1));
    });

    test('a snippet matches by name and by command', () {
      expect(search('restart', snippets: [restart]).snippets, [restart]);
      expect(search('systemctl', snippets: [restart]).snippets, [restart]);
    });

    test('a key matches by name and by type', () {
      expect(search('laptop', keys: [laptop, rsa]).keys, [laptop]);
      expect(search('rsa', keys: [laptop, rsa]).keys, [rsa]);
    });
  });

  group('a group scope', () {
    test('keeps only what is in the group, with nothing typed', () {
      final results = search(
        '',
        scope: 'Production',
        sessions: [
          session(web, mux: 'a'),
          session(pi, mux: 'b'),
        ],
        snippets: [restart],
        keys: [laptop, rsa],
      );
      expect(results.machines, unorderedEquals([web, db]));
      expect(results.sessions.single.profile, web);
      expect(results.snippets, [restart]);
      expect(results.keys, [rsa]);
      expect(results.groups, isEmpty);
    });

    test('narrows further with what is typed', () {
      expect(search('postgres', scope: 'Production').machines, [db]);
      expect(search('raspberry', scope: 'Production').machines, isEmpty);
    });
  });

  group('ranking across kinds', () {
    final inMain = profileFixture(id: 'm1', name: 'box', group: 'main');
    final alsoInMain = profileFixture(id: 'm2', name: 'other', group: 'main');
    final mainKey = sshKeyFixture(id: 'k', name: 'main', group: 'General');
    GlobalSearchResults rank(
      String query, {
      List<SshProfile> profiles = const [],
      List<Snippet> snippets = const [],
      List<SshKey> keys = const [],
    }) => globalSearch(
      query: query,
      profiles: profiles,
      groups: const [
        ProfileGroup(name: 'General'),
        ProfileGroup(name: 'main'),
      ],
      sessions: const [],
      snippets: snippets,
      keys: keys,
      generalLabel: 'General',
    );

    test('a key named after the word leads machines only filed under it', () {
      final results = rank(
        'main',
        profiles: [inMain, alsoInMain],
        keys: [mainKey],
      );
      final order = results.sections;
      expect(
        order.indexOf(SearchSection.keys),
        lessThan(order.indexOf(SearchSection.machines)),
      );
      expect(order.first, SearchSection.groups);
      expect(results.top, isA<GroupHit>());
    });

    test('a machine named after the word still leads a key holding it', () {
      final named = profileFixture(id: 'n', name: 'main');
      final key = sshKeyFixture(id: 'k2', name: 'old-main-backup');
      final results = rank('main', profiles: [named], keys: [key]);
      expect(results.sections.first, SearchSection.machines);
      expect(results.top, named);
    });

    test('a snippet named after the word leads one only running it', () {
      final byName = snippetFixture(id: 'a', name: 'nginx', command: 'x');
      final byCommand = snippetFixture(
        id: 'b',
        name: 'restart',
        command: 'systemctl restart nginx',
      );
      expect(rank('nginx', snippets: [byCommand, byName]).snippets, [
        byName,
        byCommand,
      ]);
    });

    test('a whole word beats a word merely buried in another', () {
      final word = profileFixture(id: 'w', name: 'db main eu');
      final buried = profileFixture(id: 'b', name: 'domains');
      expect(rank('main', profiles: [buried, word]).machines, [word, buried]);
    });
  });

  test('nothing typed shows recent machines and open sessions only', () {
    final live = session(web, mux: 'live');
    final detached = session(db, mux: 'old', dropped: true);
    final results = search(
      '  ',
      sessions: [live, detached],
      snippets: [restart],
      keys: [laptop],
    );
    expect(results.machines, [db, pi, web]);
    expect(results.sessions, [live]);
    expect(results.groups, isEmpty);
    expect(results.snippets, isEmpty);
    expect(results.keys, isEmpty);
  });
}
