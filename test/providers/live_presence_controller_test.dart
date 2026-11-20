import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/live_presence_provider.dart';
import 'package:termphin/services/realtime/live_presence.dart';
import 'package:termphin/services/realtime/presence_keys.dart';
import 'package:termphin/services/realtime/presence_socket.dart';
import 'package:termphin/services/realtime/presence_state.dart';

import '../support/fake_master_key_store.dart';
import '../support/fixtures.dart';

PresenceSession _session(String name) =>
    PresenceSession(name: name, createdAt: DateTime(2026), clients: 0);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late List<(String, String)> adopted;
  late Set<(String, String)> onScreen;
  late List<SshProfile> profiles;
  late LivePresenceController controller;
  late List<String> connects;
  late List<(String, Set<String>)> pruned;

  setUp(() {
    adopted = [];
    onScreen = {};
    connects = [];
    pruned = [];
    profiles = [profileFixture(id: 'profile-a')];
    controller = LivePresenceController(
      presence: LivePresence(
        connect: (url, token) async {
          connects.add(token);
          throw const PresenceRefused(503);
        },
        token: ({bool force = false}) async =>
            (token: 't', expires: DateTime(2100)),
        keys: PresenceKeyStore(cipher: cipherFixture()),
      ),
      profiles: () => profiles,
      isShown: (profileId, name) => onScreen.contains((profileId, name)),
      adopt: (profile, name) => adopted.add((profile.id, name)),
      prune: (profileId, alive) => pruned.add((profileId, alive)),
    );
    addTearDown(controller.dispose);
  });

  void report(Map<String, List<String>> names) =>
      controller.presence.onSessions!({
        for (final entry in names.entries)
          entry.key: [for (final name in entry.value) _session(name)],
      });

  test('new sessions become rows, ones on screen are left alone', () {
    onScreen.add(('profile-a', 'logs'));
    report({
      'profile-a': ['main', 'logs'],
    });
    expect(adopted, [('profile-a', 'main')]);
  });

  test('a closed row does not come back until the session is new again', () {
    report({
      'profile-a': ['main'],
    });
    expect(adopted, [('profile-a', 'main')]);
    adopted.clear();
    report({
      'profile-a': ['main'],
    });
    expect(adopted, isEmpty);
    report({'profile-a': []});
    report({
      'profile-a': ['main'],
    });
    expect(adopted, [('profile-a', 'main')]);
  });

  test('rows of sessions the report no longer lists are dropped', () {
    report({
      'profile-a': ['main', 'logs'],
    });
    report({
      'profile-a': ['main'],
    });
    expect(pruned.last.$1, 'profile-a');
    expect(pruned.last.$2, {'main'});
    report({'profile-a': []});
    expect(pruned.last.$2, isEmpty);
  });

  test('a server without a profile here shows nothing', () {
    report({
      'profile-gone': ['main'],
    });
    expect(adopted, isEmpty);
  });

  test('signing out forgets what was seen', () {
    report({
      'profile-a': ['main'],
    });
    adopted.clear();
    controller.signedIn = false;
    report({
      'profile-a': ['main'],
    });
    expect(adopted, [('profile-a', 'main')]);
  });

  test(
    'runs only signed in with Pro and live status on, in front on a phone',
    () async {
      controller.pro = true;
      controller.signedIn = true;
      await pumpEventQueue();
      expect(connects, isEmpty, reason: 'live status is off by default');
      controller.enabled = true;
      await pumpEventQueue();
      expect(connects, hasLength(1));
    },
  );
}
