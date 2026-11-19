import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../../support/fixtures.dart';
import '../../support/secure_storage_channel.dart';
import '../../support/ssh_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SshSessionManager manager;
  late String watched;
  late String other;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    final backend = FakeSshBackend();
    manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    watched = manager.adoptRemoteSession(profileFixture(id: 'a'), 'one');
    other = manager.adoptRemoteSession(profileFixture(id: 'b'), 'two');
    await manager.setActiveSession(watched);
    manager.terminalOnScreen = true;
  });

  tearDown(() => manager.dispose());

  test('a session off screen gets a dot when it notifies', () {
    var notified = 0;
    manager.addListener(() => notified++);

    manager.noteUnread(other);

    expect(manager.hasUnreadNotice(other), isTrue);
    expect(manager.hasAnyUnreadNotice, isTrue);
    expect(notified, 1);
  });

  test('the session being looked at never gets one', () {
    manager.noteUnread(watched);

    expect(manager.hasUnreadNotice(watched), isFalse);
  });

  test('a push about a machine with no tab leaves no dot', () {
    manager.noteUnread('relay:profile:session');

    expect(manager.hasAnyUnreadNotice, isFalse);
  });

  test('opening the session takes its dot away', () async {
    manager.noteUnread(other);

    await manager.setActiveSession(other);

    expect(manager.hasUnreadNotice(other), isFalse);
  });

  test('a dot on the open session from the background goes once the app is '
      'back', () {
    manager.setForeground(false);
    manager.noteUnread(watched);
    expect(manager.hasUnreadNotice(watched), isTrue);

    manager.setForeground(true);

    expect(manager.hasUnreadNotice(watched), isFalse);
  });

  test('with the terminal hidden the active session keeps its dot until the '
      'terminal is back', () {
    manager.terminalOnScreen = false;
    manager.noteUnread(watched);
    expect(manager.hasUnreadNotice(watched), isTrue);

    manager.terminalOnScreen = true;

    expect(manager.hasUnreadNotice(watched), isFalse);
  });
}
