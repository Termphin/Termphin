import 'dart:convert';

import 'package:clock/clock.dart';

import 'package:flutter_test/flutter_test.dart';
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
      expect(checks.start('m1'), isTrue);
      expect(checks.start('m1'), isFalse, reason: 'already running');
      checks.finish('m1', MachineCheck.notReady);
      expect(checks.start('m1'), isTrue);
    });

    test('a failed check waits before it runs again', () {
      final start = DateTime(2026, 11, 14, 12);
      final checks = MachineChecks();
      withClock(Clock.fixed(start), () {
        checks.start('m1');
        checks.finish('m1', MachineCheck.failed);
      });
      withClock(Clock.fixed(start.add(const Duration(seconds: 30))), () {
        expect(checks.start('m1'), isFalse);
      });
      withClock(Clock.fixed(start.add(const Duration(seconds: 61))), () {
        expect(checks.start('m1'), isTrue);
      });
    });

    test('reset lets a failed machine be tried at once', () {
      final checks = MachineChecks();
      checks.start('m1');
      checks.finish('m1', MachineCheck.failed);
      checks.reset();
      expect(checks.start('m1'), isTrue);
    });

    test('a settled check keeps reconnects quiet until forgotten', () {
      final checks = MachineChecks();
      checks.start('m1');
      checks.finish('m1', MachineCheck.settled);
      expect(checks.start('m1'), isFalse);
      checks.forget('m1');
      expect(checks.start('m1'), isTrue);
      checks.finish('m1', MachineCheck.settled);
      checks.reset();
      expect(checks.start('m1'), isTrue);
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
}
