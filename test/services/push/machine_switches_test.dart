import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/push/machine_switches.dart';
import 'package:termphin/services/push/relay_key_store.dart';

import '../../support/fixtures.dart';

void main() {
  const keys = [
    RelayServer(
      keyId: 'k1',
      label: 'web',
      profileId: 'web',
      notify: true,
      live: true,
    ),
    RelayServer(
      keyId: 'k2',
      label: 'db',
      profileId: 'db',
      notify: false,
      live: false,
    ),
    RelayServer(keyId: 'k3', label: 'legacy'),
  ];

  test('a machine never switched on is off', () {
    expect(
      machineSwitchesFor('new', pending: const {}, keys: keys),
      MachineSwitches.off,
    );
  });

  test('This computer uses its host name for relay labels and key ids', () {
    final laptop = localComputerProfile(
      name: 'This computer',
      host: 'mblaptop',
    );
    final desktop = localComputerProfile(name: 'This computer', host: 'mbpc');
    final remote = profileFixture(id: 'ssh-1', name: 'Prod', host: '10.0.0.5');

    expect(relayLabelFor(laptop), 'mblaptop');
    expect(relayProfileIdFor(laptop), 'this-computer:mblaptop');
    expect(relayProfileIdFor(desktop), isNot(relayProfileIdFor(laptop)));
    expect(relayLabelFor(remote), 'Prod');
    expect(relayProfileIdFor(remote), 'ssh-1');
  });

  test("a machine's key says what it does, for every device", () {
    expect(
      machineSwitchesFor('web', pending: const {}, keys: keys),
      const MachineSwitches(notify: true, live: true),
    );
    expect(
      machineSwitchesFor('db', pending: const {}, keys: keys),
      const MachineSwitches(),
    );
  });

  test('a switch flipped here and not on the server yet wins, and only it', () {
    expect(
      machineSwitchesFor(
        'web',
        pending: const {'web': MachineSwitchChange(notify: false)},
        keys: keys,
      ),
      const MachineSwitches(live: true),
    );
    expect(
      machineSwitchesFor(
        'new',
        pending: const {'new': MachineSwitchChange(live: true)},
        keys: keys,
      ),
      const MachineSwitches(live: true),
    );
  });

  test('changes survive being kept, and junk reads as nothing', () {
    const change = MachineSwitchChange(notify: true);
    expect(MachineSwitchChange.fromJson(change.toJson()), change);
    expect(change.toJson(), {'notify': true});
    expect(MachineSwitchChange.fromJson('on'), isNull);
    expect(
      MachineSwitchChange.fromJson(const {'notify': true, 'live': false}),
      const MachineSwitchChange(notify: true, live: false),
    );
    expect(const MachineSwitches(live: true).any, isTrue);
    expect(MachineSwitches.off.any, isFalse);
  });

  test('a later flip goes on top of one still waiting', () {
    expect(
      const MachineSwitchChange(
        notify: true,
      ).then(const MachineSwitchChange(live: false)),
      const MachineSwitchChange(notify: true, live: false),
    );
    expect(
      const MachineSwitchChange(
        notify: true,
      ).then(const MachineSwitchChange(notify: false)),
      const MachineSwitchChange(notify: false),
    );
  });

  test(
    'only a remembered key still in the account without a profileId is legacy',
    () {
      expect(isLegacyServerKey('k3', keys), isTrue);
      expect(isLegacyServerKey('k1', keys), isFalse);
      expect(isLegacyServerKey('deleted-on-another-device', keys), isFalse);
      expect(isLegacyServerKey(null, keys), isFalse);
    },
  );

  group('a key from before the switches', () {
    const old = [RelayServer(keyId: 'k', label: 'old', profileId: 'old')];

    test('shows live on, as the backend takes its reports', () {
      expect(
        machineSwitchesFor('old', pending: const {}, keys: old).live,
        isTrue,
      );
      expect(showsLive('old', pending: const {}, keys: old), isTrue);
      expect(showsLive('none', pending: const {}, keys: old), isFalse);
    });

    test("shows notifications as the machine's own earlier setting", () {
      expect(
        machineSwitchesFor(
          'old',
          pending: const {},
          keys: old,
          legacyNotify: false,
        ).notify,
        isFalse,
      );
      expect(
        machineSwitchesFor('old', pending: const {}, keys: old).notify,
        isTrue,
      );
    });

    test('flipping notifications leaves live alone, and the other way', () {
      final shown = machineSwitchesFor('old', pending: const {}, keys: old);
      expect(
        flipOf(shown, notify: true),
        const MachineSwitchChange(notify: false),
      );
      expect(flipOf(shown, live: true), const MachineSwitchChange(live: false));
      expect(
        showsLive(
          'old',
          pending: {'old': flipOf(shown, notify: true)},
          keys: old,
        ),
        isTrue,
      );
    });
  });

  group('resolveMachineSwitches', () {
    Future<bool> never() => fail('the server is not asked');

    test('notifications switched off on a key from before live leave live to '
        'the server, which still has it', () async {
      expect(
        await resolveMachineSwitches(
          change: const MachineSwitchChange(notify: false),
          key: const RelayServer(keyId: 'k', label: 'a', profileId: 'a'),
          legacyKey: false,
          hadNotifications: never,
          hadLiveStatus: () async => true,
        ),
        const MachineSwitches(live: true),
      );
    });

    test(
      'a quiet server from before the switch keeps notifications off',
      () async {
        expect(
          await resolveMachineSwitches(
            change: null,
            key: const RelayServer(keyId: 'k', label: 'b', profileId: 'b'),
            legacyKey: false,
            hadNotifications: () async => false,
            hadLiveStatus: () async => true,
          ),
          const MachineSwitches(live: true),
        );
      },
    );

    test('what the key or a flip says is not asked of the server', () async {
      expect(
        await resolveMachineSwitches(
          change: const MachineSwitchChange(live: true),
          key: const RelayServer(
            keyId: 'k',
            label: 'c',
            profileId: 'c',
            notify: true,
          ),
          legacyKey: false,
          hadNotifications: never,
          hadLiveStatus: never,
        ),
        const MachineSwitches(notify: true, live: true),
      );
    });

    test('a machine without a key starts with both off', () async {
      expect(
        await resolveMachineSwitches(
          change: null,
          key: null,
          legacyKey: false,
          hadNotifications: never,
          hadLiveStatus: never,
        ),
        MachineSwitches.off,
      );
    });

    test('a key from before keys named machines asks the server', () async {
      expect(
        await resolveMachineSwitches(
          change: null,
          key: null,
          legacyKey: true,
          hadNotifications: () async => true,
          hadLiveStatus: () async => false,
        ),
        const MachineSwitches(notify: true),
      );
    });

    test('a server that cannot be asked is no answer', () {
      expect(
        resolveMachineSwitches(
          change: null,
          key: const RelayServer(keyId: 'k', label: 'd', profileId: 'd'),
          legacyKey: false,
          hadNotifications: () async => throw StateError('exec failed'),
          hadLiveStatus: () async => true,
        ),
        throwsStateError,
      );
    });
  });
}
