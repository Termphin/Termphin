import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../../support/fixtures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('drops only offline agent rows the report no longer lists', () {
    final manager = SshSessionManager.test();
    addTearDown(manager.dispose);
    final profile = profileFixture(id: 'profile-a');
    final other = profileFixture(id: 'profile-b');
    manager.adoptRemoteSession(profile, 'main');
    manager.adoptRemoteSession(profile, 'ended');
    manager.adoptRemoteSession(
      profile,
      'plain-ssh',
      multiplexer: Multiplexer.none,
    );
    manager.adoptRemoteSession(other, 'ended');

    expect(manager.pruneReportedSessions('profile-a', {'main'}), 1);

    final left = {
      for (final tab in manager.tabs) (tab.profile.id, tab.muxName),
    };
    expect(left, {
      ('profile-a', 'main'),
      ('profile-a', 'plain-ssh'),
      ('profile-b', 'ended'),
    });
    expect(manager.pruneReportedSessions('profile-a', {'main'}), 0);
  });
}
