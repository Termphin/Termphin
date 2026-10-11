import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/ssh/ssh_prompts.dart';
import 'package:termphin/services/ssh/ssh_service.dart';

class _FakeSocket implements SSHSocket {
  @override
  Stream<Uint8List> get stream => const Stream.empty();

  @override
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;

  @override
  Future<void> get done => Future.value();

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  void destroy() {}
}

SSHUserInfoRequest requestFixture({
  String name = 'Two-factor',
  String instruction = 'Enter the code from your authenticator.',
  List<SSHUserInfoPrompt> prompts = const [],
}) => SSHUserInfoRequest(name, instruction, prompts);

void main() {
  late SshService service;

  setUp(() {
    service = SshService(
      socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
    );
  });

  test('a round with no prompts is answered without asking anyone', () async {
    var asked = 0;
    final answers = await service.answerUserInfoRequest(
      requestFixture(),
      null,
      (_) async {
        asked++;
        return const [];
      },
    );

    expect(answers, isEmpty);
    expect(asked, 0);
  });

  test('the heading reaches the connection log', () async {
    final logged = <String>[];
    await service.answerUserInfoRequest(requestFixture(), logged.add, null);

    expect(logged.single, contains('Two-factor'));
    expect(logged.single, contains('authenticator'));
  });

  test('prompts are handed over with their echo flag intact', () async {
    KeyboardInteractiveRequest? seen;
    final answers = await service.answerUserInfoRequest(
      requestFixture(
        prompts: [
          SSHUserInfoPrompt('Password: ', false),
          SSHUserInfoPrompt('Code: ', true),
        ],
      ),
      null,
      (request) async {
        seen = request;
        return ['hunter2', '123456'];
      },
    );

    expect(seen?.questions.map((q) => q.prompt), ['Password: ', 'Code: ']);
    expect(seen?.questions.map((q) => q.echo), [false, true]);
    expect(answers, ['hunter2', '123456']);
  });

  test('no way to ask cancels the round instead of answering blanks', () async {
    final answers = await service.answerUserInfoRequest(
      requestFixture(prompts: [SSHUserInfoPrompt('Code: ', true)]),
      null,
      null,
    );

    expect(answers, isNull);
  });

  test('a cancelled prompt is passed through as a cancelled round', () async {
    final answers = await service.answerUserInfoRequest(
      requestFixture(prompts: [SSHUserInfoPrompt('Code: ', true)]),
      null,
      (_) async => null,
    );

    expect(answers, isNull);
  });
}
