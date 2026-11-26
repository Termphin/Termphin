import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/push/machine_shell.dart';
import 'package:termphin/services/push/machine_switches.dart';
import 'package:termphin/services/push/push_service.dart';

/// The PowerShell script inside a command line from `powerShellCommandLine`.
String decodedScript(String commandLine) {
  final bytes = base64.decode(commandLine.split('-EncodedCommand ').last);
  final units = [
    for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
  ];
  return String.fromCharCodes(units);
}

void main() {
  group('unameSaysPosix', () {
    test('is true for the systems uname -s names', () {
      expect(unameSaysPosix('Linux\n'), isTrue);
      expect(unameSaysPosix('Darwin'), isTrue);
      expect(unameSaysPosix('FreeBSD'), isTrue);
      expect(unameSaysPosix('MINGW64_NT-10.0\n'), isTrue);
    });

    test('is false for empty output and Windows errors', () {
      expect(unameSaysPosix(''), isFalse);
      expect(
        unameSaysPosix(
          "'uname' is not recognized as an internal or external command",
        ),
        isFalse,
      );
      expect(
        unameSaysPosix("uname : The term 'uname' is not recognized"),
        isFalse,
      );
    });
  });

  group('Windows relay commands', () {
    test('the quiet check reads the relay file and changes nothing', () {
      final script = decodedScript(relayLoudnessCommandWindows());
      expect(
        script,
        contains(r"Join-Path $env:USERPROFILE '.config\termphin\relay'"),
      );
      expect(script, contains("'none'"));
      expect(script, contains("\$fields[2] -eq 'quiet'"));
      expect(script, isNot(contains('Set-Content')));
      expect(script, isNot(contains('Remove-Item')));
    });

    test('the install script writes the relay file for the current user', () {
      final script = decodedScript(
        relayInstallCommandWindows('https://relay.example/relay', 'abc.def'),
      );
      expect(script, contains('https://relay.example/relay abc.def'));
      expect(script, contains(r'.config\termphin'));
      expect(script, contains('icacls'));
      expect(script, contains('/inheritance:r'));
    });

    test('the key id script reads the id half of the token', () {
      final script = decodedScript(relayKeyIdCommandWindows());
      expect(script, contains(r'.config\termphin'));
      expect(script, contains('relay'));
    });

    test('the remove script deletes the relay file', () {
      final script = decodedScript(relayRemoveCommandWindows());
      expect(script, contains(r'.config\termphin'));
      expect(script, contains('relay'));
      expect(script, contains('Remove-Item'));
    });

    test(
      'every Windows script keeps PowerShell progress out of its output',
      () {
        for (final command in [
          relayInstallCommandWindows('https://relay.example/relay', 'abc.def'),
          relayKeyIdCommandWindows(),
          relayRemoveCommandWindows(),
        ]) {
          expect(
            decodedScript(command),
            startsWith(r"$ProgressPreference = 'SilentlyContinue'"),
          );
        }
      },
    );
  });

  group('keyIdAnswered', () {
    test('finds the id among PowerShell progress records', () {
      const output =
          '#< CLIXML\r\nkeyid1\r\n<Objs Version="1.1.0.1"><Obj S="progress"/></Objs>';
      expect(keyIdAnswered(output, 'keyid1'), isTrue);
      expect(keyIdAnswered('keyid1\n', 'keyid1'), isTrue);
    });

    test('a different, missing or empty id is not an answer', () {
      expect(keyIdAnswered('other\n', 'keyid1'), isFalse);
      expect(keyIdAnswered('', 'keyid1'), isFalse);
      expect(keyIdAnswered('\n', ''), isFalse);
    });
  });

  group('MachineChecks', () {
    test('a check not ready yet runs again at once', () {
      final checks = MachineChecks();
      final run = checks.start('m1');
      expect(run, isNotNull);
      expect(checks.start('m1'), isNull, reason: 'already running');
      checks.finish(run!, MachineCheck.notReady);
      expect(checks.start('m1'), isNotNull);
    });

    test('a failed check waits before it runs again', () {
      final start = DateTime(2026, 11, 14, 12);
      final checks = MachineChecks();
      withClock(Clock.fixed(start), () {
        checks.finish(checks.start('m1')!, MachineCheck.failed);
      });
      withClock(Clock.fixed(start.add(const Duration(seconds: 30))), () {
        expect(checks.start('m1'), isNull);
      });
      withClock(Clock.fixed(start.add(const Duration(seconds: 61))), () {
        expect(checks.start('m1'), isNotNull);
      });
    });

    test('reset lets a failed machine be tried at once', () {
      final checks = MachineChecks();
      checks.finish(checks.start('m1')!, MachineCheck.failed);
      checks.reset();
      expect(checks.start('m1'), isNotNull);
    });

    test('a settled check keeps reconnects quiet until forgotten', () {
      final checks = MachineChecks();
      checks.finish(checks.start('m1')!, MachineCheck.settled);
      expect(checks.start('m1'), isNull);
      checks.forget('m1');
      final again = checks.start('m1');
      expect(again, isNotNull);
      checks.finish(again!, MachineCheck.settled);
      checks.reset();
      expect(checks.start('m1'), isNotNull);
    });

    test('a check stuck on a server that stopped answering is given up on, '
        'and its late end changes nothing', () {
      final start = DateTime(2026, 11, 26, 12);
      final checks = MachineChecks();
      final stuck = withClock(Clock.fixed(start), () => checks.start('m1'))!;
      withClock(Clock.fixed(start.add(const Duration(seconds: 59))), () {
        expect(checks.start('m1'), isNull, reason: 'still running');
      });
      final next = withClock(
        Clock.fixed(start.add(const Duration(minutes: 1))),
        () => checks.start('m1'),
      );
      expect(next, isNotNull);
      withClock(Clock.fixed(start.add(const Duration(seconds: 90))), () {
        checks.finish(stuck, MachineCheck.failed);
        expect(checks.start('m1'), isNull, reason: 'the newer check runs');
        checks.finish(next!, MachineCheck.notReady);
        expect(checks.start('m1'), isNotNull, reason: 'no failure recorded');
      });
    });

    test('waiting for a stuck check ends when it is given up on', () {
      fakeAsync((async) {
        final checks = MachineChecks();
        withClock(async.getClock(DateTime(2026, 11, 26)), () {
          checks.start('m1');
          var idle = false;
          checks.idle('m1').then((_) => idle = true);
          async.elapse(const Duration(seconds: 59));
          expect(idle, isFalse);
          async.elapse(const Duration(seconds: 1));
          expect(idle, isTrue);
        });
      });
    });
  });

  group('unameSaysWindows', () {
    test('knows both Windows shells saying the command does not exist', () {
      expect(
        unameSaysWindows(
          "'uname' is not recognized as an internal or external command,",
        ),
        isTrue,
      );
      expect(
        unameSaysWindows("uname : The term 'uname' is not recognized as the"),
        isTrue,
      );
    });

    test('an empty or unknown answer is not Windows', () {
      expect(unameSaysWindows(''), isFalse);
      expect(unameSaysWindows('HP-UX'), isFalse);
      expect(unameSaysPosix('HP-UX'), isFalse);
    });
  });

  test(
    'tags a session the way the relay does, so its push can be taken away',
    () {
      expect(relayTag('p1', 'api'), 'relay:p1:api');
    },
  );

  group('relayTarget', () {
    test('names the machine and the session a push came from', () {
      expect(relayTarget({'profileId': 'p1', 'session': 'termphin_6d79be'}), (
        'p1',
        'termphin_6d79be',
      ));
    });

    test('keeps the machine when the server named no session', () {
      expect(relayTarget({'profileId': 'p1'}), ('p1', ''));
    });

    test('is nothing for a push that names no machine', () {
      expect(relayTarget({'kind': 'relay'}), isNull);
      expect(relayTarget({'profileId': ''}), isNull);
    });
  });

  group('relayTargetFromPayload', () {
    test('reads back what a foreground push was shown with', () {
      expect(
        relayTargetFromPayload('${kRelayPayloadPrefix}p1:termphin_ab12cd'),
        ('p1', 'termphin_ab12cd'),
      );
      expect(relayTargetFromPayload('${kRelayPayloadPrefix}p1:'), ('p1', ''));
    });

    test('leaves a terminal session id alone', () {
      expect(relayTargetFromPayload('3f2a-uuid'), isNull);
      expect(relayTargetFromPayload('$kRelayPayloadPrefix:'), isNull);
    });
  });

  test(
    'checks that branch run through sh, whatever the login shell speaks',
    () {
      for (final command in [relayKeyIdCommand, relayLoudnessCommand]) {
        expect(command, startsWith("sh -c '"));
      }
    },
  );

  test('the id check prints the key id and never its secret', () {
    expect(relayKeyIdCommand, contains('cut -d. -f1'));
    expect(relayKeyIdCommand, contains('-f2'));
  });

  test('a relay key splits into an id and a secret only the hash of which '
      'leaves the phone', () {
    final key = newRelayKey();
    expect(key.token.split('.').first, key.id);
    expect(key.secretHash, hasLength(64));
    expect(key.secretHash, isNot(contains(key.token.split('.').last)));
  });

  test(
    'the presence check only reads, and answers whether a key is there',
    () async {
      final home = await Directory.systemTemp.createTemp('presence_exists');
      addTearDown(() => home.delete(recursive: true));
      Future<String> run() async {
        final result = await Process.run(
          'sh',
          ['-c', presenceExistsCommand],
          environment: {'HOME': home.path},
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return (result.stdout as String).trim();
      }

      expect(await run(), isEmpty);
      final file = File('${home.path}/.config/termphin/presence')
        ..createSync(recursive: true);
      expect(await run(), isEmpty, reason: 'an empty file holds no key');
      file.writeAsStringSync('https://rt.termphin.dev KEY\n');
      expect(await run(), 'present');
      expect(file.readAsStringSync(), 'https://rt.termphin.dev KEY\n');
    },
    skip: Platform.isWindows,
  );

  test('a switch flipped again while a check ran waits for the next one', () {
    const on = MachineSwitches(notify: true);
    const both = MachineSwitches(notify: true, live: true);
    expect(
      pendingSettledBy(const MachineSwitchChange(notify: true), on),
      isTrue,
    );
    expect(
      pendingSettledBy(const MachineSwitchChange(notify: true), both),
      isTrue,
      reason: 'live was not flipped here',
    );
    expect(
      pendingSettledBy(const MachineSwitchChange(live: true), on),
      isFalse,
    );
    expect(pendingSettledBy(null, on), isFalse);
    expect(
      pendingSettledBy(const MachineSwitchChange(notify: true), null),
      isFalse,
    );
  });

  group('whether a machine had notifications before the switch', () {
    test('a quiet relay file means off, a loud one on', () {
      expect(hadNotificationsFrom('quiet\n', fallback: true), isFalse);
      expect(hadNotificationsFrom('loud\n', fallback: false), isTrue);
      expect(hadNotificationsFrom('none\n', fallback: false), isFalse);
      expect(hadNotificationsFrom('none\n', fallback: true), isTrue);
    });

    test('an answer that says nothing is no answer', () {
      expect(() => hadNotificationsFrom('', fallback: true), throwsStateError);
    });

    test('the check reads the quiet flag and changes nothing', () async {
      final home = await Directory.systemTemp.createTemp('relay_loudness');
      addTearDown(() => home.delete(recursive: true));
      Future<String> run() async {
        final result = await Process.run(
          'sh',
          ['-c', relayLoudnessCommand],
          environment: {'HOME': home.path},
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return (result.stdout as String).trim();
      }

      expect(await run(), 'none');
      final file = File('${home.path}/.config/termphin/relay')
        ..createSync(recursive: true);
      file.writeAsStringSync('https://relay kA.secret quiet\n');
      expect(await run(), 'quiet');
      file.writeAsStringSync('https://relay kA.secret\n');
      expect(await run(), 'loud');
      expect(file.readAsStringSync(), 'https://relay kA.secret\n');
    }, skip: Platform.isWindows);
  });

  test(
    'a machine being checked can be waited for, and then checked again',
    () async {
      final checks = MachineChecks();
      final run = checks.start('web');
      expect(run, isNotNull);
      expect(checks.start('web'), isNull);
      var idle = false;
      final waiting = checks.idle('web').then((_) => idle = true);
      await Future<void>.delayed(Duration.zero);
      expect(idle, isFalse);
      checks.finish(run!, MachineCheck.settled);
      await waiting;
      expect(idle, isTrue);
      checks.forget('web');
      expect(checks.start('web'), isNotNull);
      await checks.idle('db');
    },
  );

  test('only the keys made for the deleted machine are forgotten', () {
    const keys = [
      RelayServer(keyId: 'k1', label: 'web', profileId: 'web'),
      RelayServer(keyId: 'k2', label: 'web copy', profileId: 'web-copy'),
      RelayServer(keyId: 'k3', label: 'old'),
    ];
    expect(keysOfMachine(keys, 'web').map((key) => key.keyId), ['k1']);
    expect(keysOfMachine(keys, 'gone'), isEmpty);
  });

  group('two machines pointing at one server', () {
    const keys = [
      RelayServer(keyId: 'kA', label: 'web', profileId: 'web'),
      RelayServer(keyId: 'kB', label: 'web via vpn', profileId: 'web-vpn'),
      RelayServer(keyId: 'kOld', label: 'old'),
    ];

    test('a key made for the other machine is never this one\'s', () {
      expect(keyBelongsTo('kA', 'web-vpn', keys), isFalse);
      expect(keyBelongsTo('kB', 'web-vpn', keys), isTrue);
      expect(keyBelongsTo('kOld', 'web-vpn', keys), isTrue);
      expect(keyBelongsTo('gone', 'web-vpn', keys), isTrue);
    });

    test('only an own or an old key on the server is taken over', () {
      expect(adoptableKey('kA\n', 'web-vpn', keys), isNull);
      expect(adoptableKey('kA\n', 'web', keys), 'kA');
      expect(adoptableKey('kOld\n', 'web-vpn', keys), 'kOld');
      expect(adoptableKey('someone-else\n', 'web', keys), isNull);
      expect(adoptableKey('', 'web', keys), isNull);
    });

    test('switching one off leaves a file holding another key alone', () {
      expect(mayClearServer('kA\n', ['kB']), isFalse);
      expect(mayClearServer('someone-else\n', ['kB']), isFalse);
      expect(mayClearServer('kB\n', ['kB']), isTrue);
      expect(mayClearServer('$kNoRelayFile\n', ['kB']), isTrue);
      expect(mayClearServer('$kNoRelayFile\n', const []), isTrue);
    });

    test('an empty answer - a file that could not be read - is no proof '
        'the server holds no key', () {
      expect(mayClearServer('', ['kB']), isFalse);
      expect(mayClearServer('\n', const []), isFalse);
    });

    test('PowerShell progress records around the answer are skipped', () {
      const noise =
          '#< CLIXML\r\n$kNoRelayFile\r\n<Objs Version="1.1.0.1"><Obj S="progress"/></Objs>';
      expect(mayClearServer(noise, ['kB']), isTrue);
      expect(mayClearServer('#< CLIXML\r\nkA\r\n', ['kB']), isFalse);
    });

    test('the key id check says so when there is no relay file', () async {
      final home = await Directory.systemTemp.createTemp('relay_key_id');
      addTearDown(() => home.delete(recursive: true));
      Future<String> run() async {
        final result = await Process.run(
          'sh',
          ['-c', relayKeyIdCommand],
          environment: {'HOME': home.path},
        );
        return result.stdout as String;
      }

      expect(keyIdAnswered(await run(), kNoRelayFile), isTrue);
      final file = File('${home.path}/.config/termphin/relay')
        ..createSync(recursive: true);
      file.writeAsStringSync('https://relay kA.secret\n');
      expect(await run(), 'kA\n');
      file.writeAsStringSync('');
      expect(keyIdAnswered(await run(), kNoRelayFile), isFalse);
    }, skip: Platform.isWindows);
  });

  group('a check given up on', () {
    test('runs no more commands on the machine', () async {
      final start = DateTime(2026, 11, 26, 12);
      final checks = MachineChecks();
      final ran = <String>[];
      final shell = MachineShell('s1', (command) async {
        ran.add(command);
        return Uint8List(0);
      });
      final run = withClock(Clock.fixed(start), () => checks.start('m1'))!;
      final guarded = checks.guard(run, shell);
      await withClock(
        Clock.fixed(start.add(const Duration(seconds: 30))),
        () => guarded.exec('one'),
      );
      await withClock(
        Clock.fixed(start.add(const Duration(minutes: 1))),
        () => expectLater(guarded.exec('two'), throwsStateError),
      );
      expect(ran, ['one']);
    });
  });

  group('hadLiveStatus', () {
    test(
      'a presence key here or on the server means it had live status',
      () async {
        expect(
          await hadLiveStatus(
            heldHere: () async => true,
            askServer: () => fail('not asked'),
          ),
          isTrue,
        );
        expect(
          await hadLiveStatus(
            heldHere: () async => false,
            askServer: () async => 'present\n',
          ),
          isTrue,
        );
        expect(
          await hadLiveStatus(
            heldHere: () async => false,
            askServer: () async => '',
          ),
          isFalse,
        );
      },
    );

    test('a server that cannot be asked is not taken for one without', () {
      expect(
        hadLiveStatus(
          heldHere: () async => false,
          askServer: () async => throw StateError('exec failed'),
        ),
        throwsStateError,
      );
    });
  });
}
