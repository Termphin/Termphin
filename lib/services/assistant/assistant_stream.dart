import 'dart:convert';

/// One server-sent event: its name and its JSON data.
typedef SseEvent = ({String type, Map<String, dynamic> data});

/// Turns a stream of text lines into server-sent events. Lines that are not
/// `event:` or `data:` are ignored; an event is dispatched at the blank line
/// that ends it, and one whose data is not a JSON object is dropped.
Stream<SseEvent> parseSse(Stream<String> lines) async* {
  String? type;
  final data = StringBuffer();
  await for (final line in lines) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        final decoded = _decodeObject(data.toString());
        if (decoded != null) {
          yield (type: type ?? decoded['type'] as String? ?? '', data: decoded);
        }
      }
      type = null;
      data.clear();
      continue;
    }
    if (line.startsWith('event:')) {
      type = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(5).trimLeft());
    }
  }
}

Map<String, dynamic>? _decodeObject(String text) {
  try {
    final value = jsonDecode(text);
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null;
  }
}

/// The provider broke off a step it had started answering.
class AssistantStreamError implements Exception {
  const AssistantStreamError(this.type);

  final String type;

  @override
  String toString() => 'AssistantStreamError($type)';
}

/// Builds the assistant's message out of a step's events, block by block,
/// the way the provider would have returned it whole - thinking blocks and
/// their signatures included, so the message can be sent back unchanged in
/// the next step.
class AssistantMessageBuilder {
  final _blocks = <int, Map<String, dynamic>>{};
  final _partialInput = <int, StringBuffer>{};
  String? _stopReason;
  bool _done = false;

  /// Why the model stopped: `end_turn`, `tool_use`, `max_tokens`, ...
  String? get stopReason => _stopReason;

  /// Whether `message_stop` arrived.
  bool get done => _done;

  /// The text written so far, all text blocks joined.
  String get text => [
    for (final block in _ordered)
      if (block['type'] == 'text') block['text'] as String? ?? '',
  ].join('\n\n');

  /// The tool calls in the message, in order, with their input decoded.
  List<Map<String, dynamic>> get toolUses => [
    for (final block in _ordered)
      if (block['type'] == 'tool_use') block,
  ];

  /// The message to append to the conversation.
  Map<String, dynamic> get message => {
    'role': 'assistant',
    'content': _ordered,
  };

  List<Map<String, dynamic>> get _ordered => [
    for (final index in (_blocks.keys.toList()..sort())) _blocks[index]!,
  ];

  /// Applies one event. Throws [AssistantStreamError] for an `error` event.
  void add(SseEvent event) {
    final data = event.data;
    switch (event.type) {
      case 'content_block_start':
        final index = data['index'] as int;
        final block = Map<String, dynamic>.from(
          data['content_block'] as Map<String, dynamic>,
        );
        _blocks[index] = block;
        if (block['type'] == 'tool_use') _partialInput[index] = StringBuffer();
      case 'content_block_delta':
        final index = data['index'] as int;
        final block = _blocks[index];
        if (block == null) return;
        final delta = data['delta'] as Map<String, dynamic>;
        switch (delta['type']) {
          case 'text_delta':
            block['text'] = '${block['text'] ?? ''}${delta['text']}';
          case 'input_json_delta':
            _partialInput[index]?.write(delta['partial_json'] as String? ?? '');
          case 'thinking_delta':
            block['thinking'] =
                '${block['thinking'] ?? ''}${delta['thinking']}';
          case 'signature_delta':
            block['signature'] = delta['signature'];
        }
      case 'content_block_stop':
        final index = data['index'] as int;
        final partial = _partialInput.remove(index);
        if (partial != null && partial.isNotEmpty) {
          _blocks[index]?['input'] = jsonDecode(partial.toString());
        }
      case 'message_delta':
        final delta = data['delta'] as Map<String, dynamic>?;
        _stopReason = delta?['stop_reason'] as String? ?? _stopReason;
      case 'message_stop':
        _done = true;
      case 'error':
        final error = data['error'] as Map<String, dynamic>?;
        throw AssistantStreamError(error?['type'] as String? ?? 'unknown');
    }
  }
}
