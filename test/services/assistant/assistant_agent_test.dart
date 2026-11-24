import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terminal_view/terminal_view.dart';
import 'package:termphin/services/assistant/assistant_agent.dart';
import 'package:termphin/services/assistant/assistant_client.dart';
import 'package:termphin/services/assistant/assistant_memory.dart';
import 'package:termphin/services/assistant/assistant_session.dart';
import 'package:termphin/services/assistant/assistant_stream.dart';

import '../../support/secure_storage_channel.dart';

/// A reply the fake provider gives: text and tool calls, in order.
List<SseEvent> reply(List<Map<String, dynamic>> blocks) {
  final events = <SseEvent>[
    (
      type: 'message_start',
      data: {
        'type': 'message_start',
        'message': {'role': 'assistant'},
      },
    ),
  ];
  for (final (index, block) in blocks.indexed) {
    switch (block['type']) {
      case 'text':
        events
          ..add((
            type: 'content_block_start',
            data: {
              'index': index,
              'content_block': {'type': 'text', 'text': ''},
            },
          ))
          ..add((
            type: 'content_block_delta',
            data: {
              'index': index,
              'delta': {'type': 'text_delta', 'text': block['text']},
            },
          ));
      case 'thinking':
        events
          ..add((
            type: 'content_block_start',
            data: {
              'index': index,
              'content_block': {'type': 'thinking', 'thinking': ''},
            },
          ))
          ..add((
            type: 'content_block_delta',
            data: {
              'index': index,
              'delta': {
                'type': 'signature_delta',
                'signature': block['signature'],
              },
            },
          ));
      case 'tool_use':
        events
          ..add((
            type: 'content_block_start',
            data: {
              'index': index,
              'content_block': {
                'type': 'tool_use',
                'id': block['id'],
                'name': block['name'],
                'input': <String, dynamic>{},
              },
            },
          ))
          ..add((
            type: 'content_block_delta',
            data: {
              'index': index,
              'delta': {
                'type': 'input_json_delta',
                'partial_json': jsonEncode(block['input']),
              },
            },
          ));
    }
    events.add((type: 'content_block_stop', data: {'index': index}));
  }
  final usesTools = blocks.any((b) => b['type'] == 'tool_use');
  events
    ..add((
      type: 'message_delta',
      data: {
        'delta': {'stop_reason': usesTools ? 'tool_use' : 'end_turn'},
      },
    ))
    ..add((type: 'message_stop', data: <String, dynamic>{}));
  return events;
}

Map<String, dynamic> tool(String id, String name, Map<String, dynamic> input) =>
    {'type': 'tool_use', 'id': id, 'name': name, 'input': input};

class FakeTransport implements AssistantTransport {
  FakeTransport(this.replies);

  final List<Object> replies;
  final sent = <String>[];
  var cancelled = 0;

  final memoryFlags = <bool>[];

  @override
  double? lastUsage;

  @override
  Future<AssistantUsage?> fetchUsage() async => null;

  @override
  Stream<SseEvent> step(
    List<Map<String, dynamic>> messages, {
    bool memory = true,
  }) async* {
    memoryFlags.add(memory);
    sent.add(jsonEncode(messages));
    final next = replies.removeAt(0);
    if (next is AssistantRequestError) throw next;
    for (final event in next as List<SseEvent>) {
      yield event;
    }
  }

  @override
  void cancel() => cancelled++;
}

class FakePty implements AssistantPty {
  FakePty(this.command, {this.asks = false}) {
    if (asks) {
      _out.add(
        Uint8List.fromList(utf8.encode('Do you want to continue? [Y/n] ')),
      );
    } else {
      _finish('done: $command');
    }
  }

  final String command;
  final bool asks;
  final _out = StreamController<Uint8List>();
  final _exit = Completer<int?>();
  final typed = StringBuffer();

  void _finish(String text) {
    _out.add(Uint8List.fromList(utf8.encode('$text\r\n')));
    unawaited(_out.close());
    _exit.complete(0);
  }

  @override
  Stream<Uint8List> get output => _out.stream;

  @override
  void write(Uint8List data) {
    typed.write(utf8.decode(data));
    if (asks && typed.toString().contains('\r') && !_exit.isCompleted) {
      _finish('y\r\nInstalled.');
    }
  }

  @override
  void resize(int columns, int rows) {}

  @override
  Future<int?> get exitCode => _exit.future;

  @override
  void close() {
    if (!_exit.isCompleted) {
      unawaited(_out.close());
      _exit.complete(null);
    }
  }
}

class FakeShell implements AssistantShell {
  final commands = <String>[];
  final ptys = <FakePty>[];

  @override
  Future<AssistantPty> open(
    String command, {
    required int columns,
    required int rows,
  }) async {
    commands.add(command);
    final pty = FakePty(command, asks: command.contains('install'));
    ptys.add(pty);
    return pty;
  }

  @override
  Future<AssistantRun> run(String command, {required Duration timeout}) async {
    commands.add(command);
    if (command.startsWith('hostname')) {
      return (
        output: 'web-01\nweb-01.shop-company.pl\n',
        exitCode: 0,
        timedOut: false,
      );
    }
    if (command.startsWith('cat /var/log/big.log')) {
      return (
        output: [for (var i = 1; i <= 200; i++) 'line $i'].join('\n'),
        exitCode: 0,
        timedOut: false,
      );
    }
    return (
      output: 'mbadyl on web-01: $command ok',
      exitCode: 0,
      timedOut: false,
    );
  }
}

void main() {
  late AssistantSession session;
  late FakeShell shell;
  late AssistantMemoryStore memory;
  var memoryOn = true;
  const screen =
      'mbadyl@web-01:~\$ npm start\nError: listen EADDRINUSE :::3000';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    mockSecureStorage();
    session = AssistantSession(settleAfter: const Duration(hours: 1));
    shell = FakeShell();
    memory = AssistantMemoryStore();
    memoryOn = true;
  });

  AssistantAgent agent(FakeTransport transport, {bool connected = true}) =>
      AssistantAgent(
        session: session,
        transport: transport,
        memory: memory,
        memoryOn: () => memoryOn,
        target: () => connected
            ? (
                shell: shell,
                hosts: ['web-01'],
                users: ['mbadyl'],
                profileId: 'p1',
                readScreen: () => screen,
              )
            : null,
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('inspects, hides the server from the model and answers', () async {
    final transport = FakeTransport([
      reply([
        {'type': 'thinking', 'signature': 'sig-1'},
        {'type': 'text', 'text': 'Checking nginx on HOST_1.'},
        tool('t1', 'inspect', {
          'command': 'systemctl status nginx --no-pager',
          'purpose': 'Check nginx',
        }),
      ]),
      reply([
        {'type': 'text', 'text': 'nginx runs fine on HOST_1.'},
      ]),
    ]);
    await agent(transport).submit('Why is web-01 down?');

    expect(shell.commands, contains('systemctl status nginx --no-pager'));
    expect(transport.sent.first, isNot(contains('web-01')));
    expect(transport.sent.last, isNot(contains('web-01')));
    expect(transport.sent.last, isNot(contains('mbadyl')));
    expect(transport.sent.last, contains('"signature":"sig-1"'));
    final roles = (jsonDecode(transport.sent.last) as List)
        .map((m) => m['role'])
        .toList();
    expect(roles, ['user', 'assistant', 'user']);
    expect(session.mood, AssistantMood.done);
    final steps = session.steps;
    expect(steps[0], isA<AssistantMessage>());
    expect((steps[1] as AssistantNote).text, 'Checking nginx on web-01.');
    expect((steps[2] as AssistantCheck).status, AssistantStepStatus.done);
    expect((steps.last as AssistantNote).text, 'nginx runs fine on web-01.');
  });

  test('a long output reaches the model as its last lines only', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'inspect', {
          'command': 'cat /var/log/big.log',
          'purpose': 'Read the log',
        }),
      ]),
      reply([
        {'type': 'text', 'text': 'Done.'},
      ]),
    ]);
    await agent(transport).submit('count');
    final sent = transport.sent.last;
    expect(sent, contains('[120 earlier lines cut]'));
    expect(sent, contains('line 200'));
    expect(sent, isNot(contains('line 120\\n')));
  });

  test('a check the device cannot vouch for waits for the user', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'inspect', {
          'command': 'git branch tmp',
          'purpose': 'Make a branch',
        }),
      ]),
      reply([
        {'type': 'text', 'text': 'Done.'},
      ]),
    ]);
    final a = agent(transport);
    final done = a.submit('look');
    await settle();
    await settle();
    final index = session.steps.indexWhere((s) => s is AssistantProposal);
    final proposal = session.steps[index] as AssistantProposal;
    expect(proposal.kind, AssistantProposalKind.check);
    expect(proposal.reason, contains('git'));
    expect(session.mood, AssistantMood.waiting);
    expect(shell.commands.where((c) => c.contains('branch')), isEmpty);
    a.approve(index);
    await done;
    expect(shell.commands, contains('git branch tmp'));
    expect(transport.sent.last, contains('The user allowed it.'));
  });

  test('a check the user skips never runs, and the model hears so', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'inspect', {
          'command': 'systemctl restart nginx',
          'purpose': 'Restart',
        }),
      ]),
      reply([
        {'type': 'text', 'text': 'Fine.'},
      ]),
    ]);
    final a = agent(transport);
    final done = a.submit('fix it');
    await settle();
    await settle();
    a.skip(session.steps.indexWhere((s) => s is AssistantProposal));
    await done;
    expect(shell.commands.where((c) => c.contains('restart')), isEmpty);
    expect(transport.sent.last, contains('who did not run it'));
  });

  test('a command that never ends is refused without asking', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'inspect', {
          'command': 'tail -f /var/log/syslog',
          'purpose': 'Watch',
        }),
      ]),
      reply([
        {'type': 'text', 'text': 'OK.'},
      ]),
    ]);
    await agent(transport).submit('watch');
    expect(session.steps.whereType<AssistantProposal>(), isEmpty);
    expect(shell.commands.where((c) => c.contains('tail')), isEmpty);
    expect(transport.sent.last, contains('"is_error":true'));
  });

  test('a proposal runs only once approved', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'propose', {
          'why': 'Restart HOST_1',
          'commands': ['sudo systemctl restart shop-api'],
        }),
      ]),
      reply([
        {'type': 'text', 'text': 'Done.'},
      ]),
    ]);
    final a = agent(transport);
    final done = a.submit('fix it');
    await settle();
    await settle();
    final index = session.steps.indexWhere((s) => s is AssistantProposal);
    expect((session.steps[index] as AssistantProposal).why, 'Restart web-01');
    expect(session.mood, AssistantMood.waiting);
    expect(shell.commands.where((c) => c.contains('restart')), isEmpty);
    a.approve(index);
    await done;
    expect(shell.commands, contains('sudo systemctl restart shop-api'));
    expect(
      (session.steps[index] as AssistantProposal).state,
      AssistantProposalState.done,
    );
    expect(transport.sent.last, contains('The user approved'));
  });

  test(
    'writing instead of approving skips the proposal and passes the words on',
    () async {
      final transport = FakeTransport([
        reply([
          tool('t1', 'propose', {
            'why': 'Restart',
            'commands': ['sudo reboot'],
          }),
        ]),
        reply([
          {'type': 'text', 'text': 'Okay, only the app then.'},
        ]),
      ]);
      final a = agent(transport);
      final done = a.submit('fix it');
      await settle();
      await settle();
      await a.submit('do not reboot, restart only the app');
      await done;
      expect(shell.commands.where((c) => c.contains('reboot')), isEmpty);
      expect(transport.sent.last, contains('They said instead: do not reboot'));
      expect(session.steps.whereType<AssistantMessage>().length, 2);
    },
  );

  test('asks before reading a file that may hold secrets', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'read_file', {
          'path': '/srv/shop/.env',
          'purpose': 'Read env',
          'lines': 50,
        }),
      ]),
      reply([
        {'type': 'text', 'text': 'Understood.'},
      ]),
    ]);
    final a = agent(transport);
    final done = a.submit('check config');
    await settle();
    await settle();
    final index = session.steps.indexWhere((s) => s is AssistantProposal);
    expect(
      (session.steps[index] as AssistantProposal).kind,
      AssistantProposalKind.readSecret,
    );
    expect(shell.commands.where((c) => c.contains('.env')), isEmpty);
    a.skip(index);
    await done;
    expect(shell.commands.where((c) => c.contains('.env')), isEmpty);
    expect(transport.sent.last, contains('did not let you read'));
  });

  test('answers a question with the next message', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'ask_user', {'question': 'Which site?'}),
      ]),
      reply([
        {'type': 'text', 'text': 'Thanks.'},
      ]),
    ]);
    final a = agent(transport);
    final done = a.submit('fix the site');
    await settle();
    await settle();
    expect(session.mood, AssistantMood.waiting);
    await a.submit('the shop');
    await done;
    expect(transport.sent.last, contains('the shop'));
  });

  test('says why when the service refuses', () async {
    final transport = FakeTransport([
      const AssistantRequestError('pro_required', status: 403),
    ]);
    await agent(transport).submit('hi');
    expect(
      (session.steps.last as AssistantFailure).kind,
      AssistantFailureKind.proRequired,
    );
    expect(session.mood, AssistantMood.failed);
  });

  test('needs a connected session', () async {
    await agent(FakeTransport([]), connected: false).submit('hi');
    expect(
      (session.steps.last as AssistantFailure).kind,
      AssistantFailureKind.noConnection,
    );
  });

  test('after a stop the conversation still alternates', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'propose', {
          'why': 'x',
          'commands': ['sudo true'],
        }),
      ]),
      reply([
        {'type': 'text', 'text': 'Back.'},
      ]),
    ]);
    final a = agent(transport);
    final done = a.submit('one');
    await settle();
    await settle();
    a.stop();
    await done;
    await a.submit('two');
    final messages = jsonDecode(transport.sent.last) as List;
    expect(messages.map((m) => m['role']).toList(), [
      'user',
      'assistant',
      'user',
    ]);
    final last = jsonEncode(messages.last);
    expect(last, contains('tool_result'));
    expect(last, contains('two'));
  });

  test(
    'a malformed proposal never reaches the user; the model is asked again',
    () async {
      final transport = FakeTransport([
        reply([
          tool('t1', 'propose', {
            'why':
                'Disable autostart.</why>\n<parameter name="commands">["systemctl --user disable hermes-gateway.service"]',
            'commands': <String>[],
          }),
        ]),
        reply([
          tool('t2', 'propose', {
            'why': 'Disable autostart.',
            'commands': ['systemctl --user disable hermes-gateway.service'],
          }),
        ]),
        reply([
          {'type': 'text', 'text': 'Done.'},
        ]),
      ]);
      final a = agent(transport);
      final done = a.submit('disable it');
      for (var i = 0; i < 6; i++) {
        await settle();
      }
      final proposals = session.steps.whereType<AssistantProposal>().toList();
      expect(proposals, hasLength(1));
      expect(proposals.single.why, 'Disable autostart.');
      expect(proposals.single.commands, [
        'systemctl --user disable hermes-gateway.service',
      ]);
      expect(transport.sent[1], contains('malformed'));
      a.approve(session.steps.indexOf(proposals.single));
      await done;
    },
  );

  test('an inspect call with markup in it is not run', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'inspect', {
          'command': 'df -h</command><parameter name="purpose">x',
          'purpose': 'Disk',
        }),
      ]),
      reply([
        {'type': 'text', 'text': 'ok'},
      ]),
    ]);
    await agent(transport).submit('disk');
    expect(shell.commands.where((c) => c.contains('df')), isEmpty);
    expect(transport.sent.last, contains('malformed'));
  });

  test(
    'an approved command that asks runs in a terminal the user answers',
    () async {
      final transport = FakeTransport([
        reply([
          tool('t1', 'propose', {
            'why': 'Install it',
            'commands': ['sudo apt install htop'],
          }),
        ]),
        reply([
          {'type': 'text', 'text': 'Installed.'},
        ]),
      ]);
      final a = agent(transport);
      final done = a.submit('install htop');
      for (var i = 0; i < 4; i++) {
        await settle();
      }
      final index = session.steps.indexWhere((s) => s is AssistantProposal);
      a.approve(index);
      for (var i = 0; i < 6; i++) {
        await settle();
      }
      final proposal = session.steps[index] as AssistantProposal;
      expect(proposal.state, AssistantProposalState.running);
      final terminal = proposal.terminal!;
      expect(
        terminal.buffer.getText(),
        contains('Do you want to continue? [Y/n]'),
      );
      terminal.textInput('y');
      terminal.keyInput(TerminalKey.enter);
      await done;
      expect(shell.ptys.single.typed.toString(), 'y\r');
      expect(
        (session.steps[index] as AssistantProposal).state,
        AssistantProposalState.done,
      );
      final sent = transport.sent.last;
      expect(sent, contains(r'$ sudo apt install htop'));
      expect(sent, contains('Installed.'));
      expect(sent, contains('exit code 0'));
    },
  );

  test(
    'reads the screen when asked about it, hidden like everything else',
    () async {
      final transport = FakeTransport([
        reply([tool('t1', 'read_screen', <String, dynamic>{})]),
        reply([
          {'type': 'text', 'text': 'Port 3000 is taken.'},
        ]),
      ]);
      await agent(transport).submit('what is this error?');
      final check = session.steps.whereType<AssistantCheck>().single;
      expect(check.screen, isTrue);
      expect(transport.sent.last, contains('EADDRINUSE'));
      expect(transport.sent.last, isNot(contains('web-01')));
      expect(transport.sent.last, isNot(contains('mbadyl')));
    },
  );

  test('remembers a fact, shows it, and sends it next conversation', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'remember', {
          'note': 'The shop runs as shop-api on HOST_1.',
        }),
      ]),
      reply([
        {'type': 'text', 'text': 'Noted.'},
      ]),
    ]);
    await agent(transport).submit('the shop is shop-api');
    expect(await memory.notesFor('p1'), [
      'The shop runs as shop-api on web-01.',
    ]);
    expect(
      session.steps.whereType<AssistantRemembered>().single.note,
      'The shop runs as shop-api on web-01.',
    );

    session.reset();
    final next = FakeTransport([
      reply([
        {'type': 'text', 'text': 'It is shop-api.'},
      ]),
    ]);
    await agent(next).submit('what runs the shop?');
    expect(next.sent.single, contains('Notes saved about this server earlier'));
    expect(next.sent.single, contains('shop-api on HOST_1'));
    expect(next.memoryFlags.single, isTrue);
  });

  test('with memory off nothing is saved or sent', () async {
    await memory.add('p1', 'An old note.');
    memoryOn = false;
    final transport = FakeTransport([
      reply([
        tool('t1', 'remember', {'note': 'Something new.'}),
      ]),
      reply([
        {'type': 'text', 'text': 'Ok.'},
      ]),
    ]);
    await agent(transport).submit('hi');
    expect(transport.sent.first, isNot(contains('An old note')));
    expect(transport.memoryFlags, everyElement(isFalse));
    expect(await memory.notesFor('p1'), ['An old note.']);
    expect(session.steps.whereType<AssistantRemembered>(), isEmpty);
  });

  test('a note that looks like a secret is not saved', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'remember', {'note': 'DB_PASSWORD=hunter2hunter2'}),
      ]),
      reply([
        {'type': 'text', 'text': 'Ok.'},
      ]),
    ]);
    await agent(transport).submit('remember the password');
    expect(await memory.notesFor('p1'), isEmpty);
  });

  test('says once when most of the allowance is used', () async {
    final transport = FakeTransport([
      reply([
        tool('t1', 'inspect', {'command': 'df -h', 'purpose': 'Disk'}),
      ]),
      reply([
        {'type': 'text', 'text': 'Done.'},
      ]),
    ])..lastUsage = 0.85;
    await agent(transport).submit('disk?');
    expect(session.steps.whereType<AssistantUsageNotice>().single.used, 0.85);
  });
}
