import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/realtime/presence_device.dart';
import 'package:termphin/services/realtime/presence_state.dart';
import 'package:termphin/services/security/aead.dart';

Uint8List _key() => Uint8List.fromList(List<int>.generate(32, (i) => i));

const _keyId = 'AbCdEfGhIjKlMnOpQrStUv';

String _seal(Uint8List key, String keyId, Object plaintext) {
  final sealed = sealBytes(
    key,
    utf8Bytes(jsonEncode(plaintext)),
    aad: presenceAad(keyId),
    random: Random(1),
  );
  return sealed.substring(sealPrefix.length);
}

void main() {
  test('opens the vector termphin-agent and Node seal identically', () {
    const vector =
        'BwcHBwcHBwcHBwcHdEjQflU++9ayvymxrHOH/tIv5BzmhKMjpeYj3yyDh58jiuVtvI1R+oTeLQ==';
    final opened = openPresenceState(_key(), _keyId, vector);
    expect(opened, isNotNull);
    expect(opened!.writtenAt, 1);
    expect(opened.sessions, isEmpty);
  });

  test('reads the sessions the agent lists', () {
    final state = _seal(_key(), _keyId, {
      'v': 1,
      't': 1763600000000,
      'sessions': [
        {'name': 'main', 'created': 1763600000, 'clients': 2},
      ],
    });
    final opened = openPresenceState(_key(), _keyId, state)!;
    expect(opened.writtenAt, 1763600000000);
    expect(opened.sessions.single.name, 'main');
    expect(opened.sessions.single.clients, 2);
    expect(
      opened.sessions.single.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1763600000 * 1000),
    );
  });

  test('reads which devices are attached, skipping what it cannot read', () {
    final state = _seal(_key(), _keyId, {
      'v': 1,
      't': 2,
      'sessions': [
        {
          'name': 'main',
          'created': 1,
          'clients': 2,
          'devices': ['id1;desktop;T2ZmaWNlIFBD', 'garbage', 7],
        },
        {'name': 'old', 'created': 1, 'clients': 0},
      ],
    });
    final sessions = openPresenceState(_key(), _keyId, state)!.sessions;
    expect(sessions[0].devices.single.name, 'Office PC');
    expect(sessions[0].devices.single.kind, PresenceDeviceKind.desktop);
    expect(sessions[1].devices, isEmpty);
  });

  test('reads what each session is doing', () {
    final state = _seal(_key(), _keyId, {
      'v': 1,
      't': 3,
      'sessions': [
        {
          'name': 'agent',
          'created': 1,
          'clients': 0,
          'activity': {'state': 'waiting', 'command': 'claude'},
        },
        {
          'name': 'shell',
          'created': 1,
          'clients': 0,
          'activity': {'state': 'idle', 'command': null},
        },
        {
          'name': 'odd',
          'created': 1,
          'clients': 0,
          'activity': {'state': 'dancing'},
        },
        {'name': 'old', 'created': 1, 'clients': 0},
      ],
    });
    final sessions = openPresenceState(_key(), _keyId, state)!.sessions;
    expect(sessions[0].activity!.state, SessionActivityState.waiting);
    expect(sessions[0].activity!.command, 'claude');
    expect(sessions[1].activity!.state, SessionActivityState.idle);
    expect(sessions[1].activity!.command, isNull);
    expect(sessions[2].activity, isNull);
    expect(sessions[3].activity, isNull);
  });

  test('reads what a program says it is doing', () {
    final state = _seal(_key(), _keyId, {
      'v': 1,
      't': 3,
      'sessions': [
        {
          'name': 'agent',
          'created': 1,
          'clients': 0,
          'activity': {
            'state': 'waiting',
            'command': 'claude',
            'program': {
              'state': 'blocked',
              'kind': 'permission',
              'app': 'claude-code',
              'msg': 'approve Bash',
            },
          },
        },
        {
          'name': 'odd',
          'created': 1,
          'clients': 0,
          'activity': {
            'state': 'running',
            'program': {'state': 'sleeping', 'app': 'x'},
          },
        },
        {
          'name': 'older',
          'created': 1,
          'clients': 0,
          'activity': {'state': 'running', 'command': 'codex'},
        },
      ],
    });
    final sessions = openPresenceState(_key(), _keyId, state)!.sessions;
    final program = sessions[0].activity!.program!;
    expect(program.state, ProgramState.blocked);
    expect(program.block, ProgramBlock.permission);
    expect(program.app, 'claude-code');
    expect(program.message, 'approve Bash');
    expect(sessions[1].activity!.program, isNull);
    expect(sessions[2].activity!.program, isNull);
  });

  test('programs are named the way people say them', () {
    expect(programName('claude-code'), 'Claude Code');
    expect(programName('codex'), 'Codex');
    expect(programName('antigravity'), 'Antigravity');
    expect(programName('newthing'), 'newthing');
  });

  test('reads which sessions a reboot left to restore', () {
    final state = _seal(_key(), _keyId, {
      'v': 1,
      't': 4,
      'sessions': [
        {'name': 'live', 'created': 1, 'clients': 0},
        {
          'name': 'rebooted',
          'created': 1,
          'clients': 0,
          'devices': <Object>[],
          'restorable': true,
        },
      ],
    });
    final sessions = openPresenceState(_key(), _keyId, state)!.sessions;
    expect(sessions.map((s) => s.restorable), [false, true]);
  });

  test('a state sealed for another server or key does not open', () {
    final state = _seal(_key(), _keyId, {
      'v': 1,
      't': 1,
      'sessions': <Object>[],
    });
    expect(openPresenceState(_key(), 'OtherServerKeyId', state), isNull);
    final otherKey = Uint8List.fromList(List<int>.filled(32, 9));
    expect(openPresenceState(otherKey, _keyId, state), isNull);
  });

  test('nothing, garbage and the wrong shape do not open', () {
    expect(openPresenceState(_key(), _keyId, ''), isNull);
    expect(openPresenceState(_key(), _keyId, 'not base64!'), isNull);
    for (final plaintext in [
      {'v': 2, 't': 1, 'sessions': <Object>[]},
      {'v': 1, 't': '1', 'sessions': <Object>[]},
      {'v': 1, 't': 1, 'sessions': 'main'},
      {
        'v': 1,
        't': 1,
        'sessions': [
          {'name': 1, 'created': 1, 'clients': 1},
        ],
      },
    ]) {
      expect(
        openPresenceState(_key(), _keyId, _seal(_key(), _keyId, plaintext)),
        isNull,
        reason: '$plaintext',
      );
    }
  });

  test('an older state is refused, the newest is accepted again', () {
    final freshness = PresenceFreshness();
    expect(freshness.accept('a', 10), isTrue);
    expect(freshness.accept('a', 10), isTrue);
    expect(freshness.accept('a', 9), isFalse);
    expect(freshness.accept('b', 1), isTrue);
    freshness.clear();
    expect(freshness.accept('a', 9), isTrue);
  });

  test('a server whose clock ran ahead is followed again once it is set '
      'back', () {
    final now = DateTime.utc(2026, 11, 21, 8).millisecondsSinceEpoch;
    final freshness = PresenceFreshness(now: () => now);
    const hours = 60 * 60 * 1000;
    expect(freshness.accept('a', now + 8 * hours), isTrue);
    expect(freshness.accept('a', now), isTrue);
    expect(freshness.accept('a', now - 1000), isFalse);
  });

  test(
    'the list from the agent itself reads as sessions with devices and activity',
    () {
      final sessions = parseAgentSessionLines(
        'termphin_a\t1\t1795261040\t2\tpix;phone;UGl4ZWw,mac;desktop;TWFj\t'
        'working;c2xlZXAgMQ\n'
        'termphin_b\t1\t1795261000\t0\t\tidle\n'
        'old\t1\t1795260000\t1\n'
        'broken line\n',
      );

      expect(sessions.map((s) => s.name), ['termphin_a', 'termphin_b', 'old']);
      final a = sessions.first;
      expect(a.clients, 2);
      expect(a.devices.map((d) => d.name), ['Pixel', 'Mac']);
      expect(a.activity?.state, SessionActivityState.working);
      expect(a.activity?.command, 'sleep 1');
      expect(a.createdAt, DateTime.fromMillisecondsSinceEpoch(1795261040000));
      expect(sessions[1].activity?.state, SessionActivityState.idle);
      expect(sessions[1].devices, isEmpty);
      expect(sessions[2].activity, isNull);
    },
  );
}
