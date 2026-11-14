import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/active_session.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/terminal/terminal_text.dart';

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

  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  String shownBy(ActiveSessionView session) {
    session.terminal.flush();
    return terminalBufferText(session.terminal.terminal.buffer);
  }

  test('parses output into its terminal while no pane is showing it', () {
    final session = createSession();

    session.deliverOutput(bytes('one\r\n'));
    session.deliverOutput(bytes('two'));

    expect(shownBy(session), 'one\ntwo');
    session.dispose();
  });

  test('delivers live output to an active listener', () async {
    final session = createSession();
    final outputFuture = session.outputStream.first;

    session.deliverOutput(Uint8List.fromList([5, 6]));

    expect((await outputFuture).toList(), [5, 6]);
    session.dispose();
  });

  test('keeps parsing after a listener cancels', () async {
    final session = createSession();
    final subscription = session.outputStream.listen((_) {});
    await subscription.cancel();

    session.deliverOutput(bytes('still here'));

    expect(shownBy(session), 'still here');
    session.dispose();
  });

  test('copies delivered bytes before queueing them', () {
    final session = createSession();
    final delivered = bytes('ab');

    session.deliverOutput(delivered);
    delivered[0] = 0x7a;

    expect(shownBy(session), 'ab');
    session.dispose();
  });

  test('keeps what was said before a long run of redraws', () {
    final session = createSession();
    for (var line = 1; line <= 300; line++) {
      session.deliverOutput(bytes('answer line $line\r\n'));
    }
    const frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
    var redrawn = 0;
    for (var tick = 0; redrawn < 700 * 1024; tick++) {
      final frame = bytes(
        '\r\x1b[2K\x1b[38;5;208m${frames[tick % 10]}\x1b[39m '
        'Thinking… (${tick ~/ 10}s · esc to interrupt)',
      );
      redrawn += frame.length;
      session.deliverOutput(frame);
    }
    session.deliverOutput(bytes('\r\x1b[2Kdone\r\n'));

    final shown = shownBy(session).split('\n');

    expect(shown.first, 'answer line 1');
    expect(shown, hasLength(301));
    expect(shown.last, 'done');
    session.dispose();
  });

  test('stops parsing on dispose', () {
    final session = createSession();
    final terminal = session.terminal;
    session.deliverOutput(bytes('before'));
    terminal.flush();

    session.dispose();
    terminal
      ..add(bytes(' after'))
      ..flush();

    expect(terminalBufferText(terminal.terminal.buffer), 'before');
  });

  test('ignores output after dispose', () {
    final session = createSession();
    session.dispose();

    expect(
      () => session.deliverOutput(Uint8List.fromList([1])),
      returnsNormally,
    );
  });

  test('a tab restored without a terminal gets one at the size its pty '
      'opens with', () {
    final restored = createSession()..ptyOpensAt(132, 50);
    final laidOut = createSession();
    laidOut.terminal.terminal.resize(100, 30);
    laidOut.ptyOpensAt(132, 50);

    expect(restored.terminal.terminal.viewWidth, 132);
    expect(restored.terminal.terminal.viewHeight, 50);
    expect(laidOut.terminal.terminal.viewWidth, 100);
    restored.dispose();
    laidOut.dispose();
  });

  test('a replay arriving after dispose starts nothing', () {
    final session = createSession();
    final terminal = session.terminal;
    session.dispose();

    session.restartTerminal(bytes('late'));

    expect(session.terminal, same(terminal));
  });

  group('a replay that replaces what was there', () {
    test('starts a new terminal from it, at the size of the old one', () {
      final session = createSession();
      session.deliverOutput(bytes('stale'));
      final replaced = session.terminal..flush();
      replaced.terminal.resize(100, 30);

      session.restartTerminal(bytes('fresh'));

      expect(session.terminal, isNot(same(replaced)));
      expect(shownBy(session), 'fresh');
      expect(session.terminal.terminal.viewWidth, 100);
      expect(session.terminal.terminal.viewHeight, 30);
      session.dispose();
    });

    test('leaves the old terminal as it stood, for the pane still on it', () {
      final session = createSession();
      session.deliverOutput(bytes('stale'));
      final replaced = session.terminal..flush();

      session.restartTerminal(bytes('fresh'));
      replaced
        ..add(bytes(' and late'))
        ..flush();

      expect(terminalBufferText(replaced.terminal.buffer), 'stale');
      session.dispose();
    });

    test('takes live output after it', () {
      final session = createSession();

      session.restartTerminal(bytes('fresh\r\n'));
      session.deliverOutput(bytes('live'));

      expect(shownBy(session), 'fresh\nlive');
      session.dispose();
    });
  });
}
