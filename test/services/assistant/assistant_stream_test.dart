import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/assistant/assistant_client.dart';
import 'package:termphin/services/assistant/assistant_stream.dart';

void main() {
  test('parses server-sent events and skips what is not JSON', () async {
    final events = await parseSse(
      Stream.fromIterable([
        'event: message_start',
        'data: {"type":"message_start"}',
        '',
        ': keep-alive',
        'event: ping',
        'data: not json',
        '',
        'event: content_block_delta',
        'data: {"index":0,',
        'data: "delta":{"type":"text_delta","text":"hi"}}',
        '',
      ]),
    ).toList();
    expect(events.map((e) => e.type), ['message_start', 'content_block_delta']);
    expect(events.last.data['delta'], {'type': 'text_delta', 'text': 'hi'});
  });

  test('an error event breaks the step off', () {
    final builder = AssistantMessageBuilder();
    expect(
      () => builder.add((
        type: 'error',
        data: {
          'error': {'type': 'provider'},
        },
      )),
      throwsA(isA<AssistantStreamError>()),
    );
  });

  test('the step address follows the build', () {
    expect(
      assistantStepUri(env: 'prod', base: 'https://rt.example').toString(),
      'https://rt.example/v1/assistant/step',
    );
    expect(
      assistantStepUri(env: 'dev', base: 'https://rt.example').toString(),
      'https://rt.example/dev/v1/assistant/step',
    );
    expect(
      assistantStepUri(env: 'dev', base: 'https://rt.example/dev').toString(),
      'https://rt.example/dev/v1/assistant/step',
    );
    expect(
      assistantStepUri(env: 'dev', base: 'https://rt.example/dev/').toString(),
      'https://rt.example/dev/v1/assistant/step',
    );
  });
}
