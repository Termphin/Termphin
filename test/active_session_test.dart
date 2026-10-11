import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_view/terminal_view.dart';
import 'package:termphin/models/active_session.dart';
import 'package:termphin/models/ssh_profile.dart';

void main() {
  ActiveSessionView createSession() => ActiveSessionView(
    id: 'session',
    profile: SshProfile(
      id: 'profile',
      name: 'Server',
      host: 'example.com',
      port: 22,
      username: 'user',
      authMethod: AuthMethod.none,
      createdAt: DateTime(2026),
    ),
    connectedAt: DateTime(2026),
  );

  test('records output in raw history while nothing is listening', () {
    final session = createSession();

    session.deliverOutput(Uint8List.fromList([1, 2]));
    session.deliverOutput(Uint8List.fromList([3, 4]));

    expect(session.rawHistorySnapshot.toList(), [1, 2, 3, 4]);
    session.dispose();
  });

  test('delivers live output to an active listener', () async {
    final session = createSession();
    final outputFuture = session.outputStream.first;

    session.deliverOutput(Uint8List.fromList([5, 6]));

    expect((await outputFuture).toList(), [5, 6]);
    session.dispose();
  });

  test('keeps recording history after a listener cancels', () async {
    final session = createSession();
    final subscription = session.outputStream.listen((_) {});
    await subscription.cancel();

    session.deliverOutput(Uint8List.fromList([7, 8]));

    expect(session.rawHistorySnapshot.toList(), [7, 8]);
    session.dispose();
  });

  test('copies delivered bytes before recording them', () {
    final session = createSession();
    final bytes = Uint8List.fromList([1, 2]);

    session.deliverOutput(bytes);
    bytes[0] = 9;

    expect(session.rawHistorySnapshot.toList(), [1, 2]);
    session.dispose();
  });

  test('trims raw history once it outgrows the cap', () {
    final session = createSession();
    final chunk = Uint8List(64 * 1024);

    for (var i = 0; i < 16; i++) {
      session.deliverOutput(chunk);
    }

    expect(session.rawHistorySnapshot.length, lessThanOrEqualTo(512 * 1024));
    session.dispose();
  });

  test('drops history on dispose', () {
    final session = createSession();
    session.deliverOutput(Uint8List.fromList([1, 2]));

    session.dispose();

    expect(session.rawHistorySnapshot, isEmpty);
  });

  test('ignores output after dispose', () {
    final session = createSession();
    session.dispose();

    expect(
      () => session.deliverOutput(Uint8List.fromList([1])),
      returnsNormally,
    );
  });

  group('a snapshot whose start was trimmed away', () {
    Terminal rebuiltFrom(ActiveSessionView session) {
      final terminal = Terminal();
      terminal.write(utf8.decode(session.rawHistorySnapshot));
      return terminal;
    }

    void outgrowTheCap(ActiveSessionView session) {
      final screenful = Uint8List.fromList(utf8.encode('\x1b[H${'x' * 4096}'));
      for (var i = 0; i < 200; i++) {
        session.deliverOutput(screenful);
      }
    }

    test('still puts a full-screen program back on the alt screen with its '
        'mouse reporting, so it keeps owning the scroll', () {
      final session = createSession();
      session.deliverOutput(
        Uint8List.fromList(utf8.encode('\x1b[?1049h\x1b[?1000;1006h')),
      );
      outgrowTheCap(session);

      final terminal = rebuiltFrom(session);

      expect(terminal.isUsingAltBuffer, isTrue);
      expect(terminal.mouseMode, isNot(MouseMode.none));
      session.dispose();
    });

    test('does not restore a mode the program already turned off', () {
      final session = createSession();
      session.deliverOutput(
        Uint8List.fromList(
          utf8.encode('\x1b[?1049h\x1b[?1000h\x1b[?1000l\x1b[?1049l'),
        ),
      );
      outgrowTheCap(session);

      final terminal = rebuiltFrom(session);

      expect(terminal.isUsingAltBuffer, isFalse);
      expect(terminal.mouseMode, MouseMode.none);
      session.dispose();
    });

    test('picks up a mode sequence split across two chunks', () {
      final session = createSession();
      session.deliverOutput(Uint8List.fromList(utf8.encode('\x1b[?10')));
      session.deliverOutput(Uint8List.fromList(utf8.encode('49h')));
      outgrowTheCap(session);

      expect(rebuiltFrom(session).isUsingAltBuffer, isTrue);
      session.dispose();
    });

    test('keeps the modes a replaced history was trimmed of', () {
      final session = createSession();
      final replay = BytesBuilder()
        ..add(utf8.encode('\x1b[?1049h'))
        ..add(Uint8List(600 * 1024));
      session.replaceHistory(replay.takeBytes());

      expect(rebuiltFrom(session).isUsingAltBuffer, isTrue);
      session.dispose();
    });
  });
}
