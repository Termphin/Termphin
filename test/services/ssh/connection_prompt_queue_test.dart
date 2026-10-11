import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/known_host.dart';
import 'package:termphin/services/ssh/ssh_prompts.dart';

void main() {
  const hostKeyRequest = HostKeyPromptRequest(
    host: 'example.com',
    port: 22,
    keyType: 'ssh-ed25519',
    fingerprint: 'SHA256:aaa',
    verdict: HostKeyVerdict.unknown,
  );
  const interactiveRequest = KeyboardInteractiveRequest(
    name: '',
    instruction: '',
    questions: [KeyboardInteractiveQuestion(prompt: 'Code:', echo: false)],
  );

  test(
    'a second host key question waits for the first to be answered',
    () async {
      final queue = ConnectionPromptQueue();
      final pending = <Completer<bool>>[];
      final prompt = queue.hostKey((_) {
        final completer = Completer<bool>();
        pending.add(completer);
        return completer.future;
      });

      final first = prompt(hostKeyRequest);
      final second = prompt(hostKeyRequest);
      await Future<void>.delayed(Duration.zero);

      expect(pending.length, 1);

      pending.first.complete(true);
      expect(await first, isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(pending.length, 2);
      pending.last.complete(false);
      expect(await second, isFalse);
    },
  );

  test('a question refused by the user does not block the next one', () async {
    final queue = ConnectionPromptQueue();
    var asked = 0;
    final prompt = queue.hostKey((_) async {
      asked++;
      throw StateError('no navigator');
    });

    await expectLater(prompt(hostKeyRequest), throwsStateError);
    await expectLater(prompt(hostKeyRequest), throwsStateError);

    expect(asked, 2);
  });

  test('host key and keyboard-interactive share one queue', () async {
    final queue = ConnectionPromptQueue();
    final hostKeyAnswer = Completer<bool>();
    var interactiveAsked = false;

    final hostKey = queue.hostKey((_) => hostKeyAnswer.future);
    final interactive = queue.keyboardInteractive((_) async {
      interactiveAsked = true;
      return const ['123456'];
    });

    final pendingHostKey = hostKey(hostKeyRequest);
    final pendingInteractive = interactive(interactiveRequest);
    await Future<void>.delayed(Duration.zero);

    expect(interactiveAsked, isFalse);

    hostKeyAnswer.complete(true);
    await pendingHostKey;
    expect(await pendingInteractive, ['123456']);
  });
}
