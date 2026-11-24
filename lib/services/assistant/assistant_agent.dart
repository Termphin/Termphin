import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:terminal_view/terminal_view.dart';

import '../ssh/remote_agent_service.dart' show shellQuote;
import 'assistant_client.dart';
import 'assistant_commands.dart';
import 'assistant_memory.dart';
import 'assistant_redactor.dart';
import 'assistant_session.dart';
import 'assistant_stream.dart';
import 'server_system.dart';

/// What a command run for the assistant printed and how it ended.
typedef AssistantRun = ({String output, int? exitCode, bool timedOut});

/// Runs commands on the server a conversation is about, in a channel of
/// its own beside the user's terminal.
abstract class AssistantShell {
  Future<AssistantRun> run(String command, {required Duration timeout});

  /// Starts [command] with a terminal of [columns] by [rows], for commands
  /// the user may have to answer.
  Future<AssistantPty> open(
    String command, {
    required int columns,
    required int rows,
  });
}

/// A command running in a terminal: what it prints, what the user types
/// into it, and how it ended.
abstract class AssistantPty {
  Stream<Uint8List> get output;

  void write(Uint8List data);

  void resize(int columns, int rows);

  /// The exit code once the command ends, null when it reported none.
  Future<int?> get exitCode;

  void close();
}

/// The server a conversation is bound to: how to run commands there, and
/// the names that identify it, for [AssistantRedactor].
typedef AssistantTarget = ({
  AssistantShell shell,
  List<String> hosts,
  List<String> users,
  String profileId,
  String? Function() readScreen,
  bool windows,
});

/// Runs the assistant: sends the conversation a step at a time, shows what
/// the model says as it arrives, and carries out its tool calls - `inspect`
/// only when [refuseInspect] lets it, `read_file` after asking when the file
/// may hold secrets, `propose` only once the user approves, `ask_user` with
/// the user's next message - until the model stops calling tools.
///
/// Everything sent passes through the conversation's [AssistantRedactor]
/// and everything shown or run comes back through it. A conversation is
/// bound to the server it started on; a new chat binds to whichever is
/// active then.
class AssistantAgent {
  AssistantAgent({
    required this.session,
    required this.transport,
    required this.target,
    required this.memory,
    required this.memoryOn,
    this.maxSteps = 30,
  });

  /// Where notes about servers are kept.
  final AssistantMemoryStore memory;

  /// Whether memory is on, read at each step.
  final bool Function() memoryOn;

  final AssistantSession session;
  final AssistantTransport transport;

  /// The active session's server, or null when none is connected.
  final AssistantTarget? Function() target;

  /// Steps one message may take before the assistant gives up.
  final int maxSteps;

  static const _inspectTimeout = Duration(seconds: 20);

  /// How long an approved command may run, waiting for the user's answers
  /// included.
  static const _answerTimeout = Duration(minutes: 15);

  /// How much of a command's output reaches the model: its last lines, up
  /// to this many characters. Every result stays in the conversation and
  /// is sent again with each later step, so a long one is paid for many
  /// times; the model is told to read narrowly, with grep and tail, and can
  /// ask for more.
  static const _keepLines = 80;
  static const _keepChars = 4000;

  final _messages = <Map<String, dynamic>>[];
  AssistantTarget? _target;
  AssistantRedactor? _redactor;
  int _run = 0;
  Completer<String>? _answer;

  /// The approved command running now, closed by [stop].
  AssistantPty? _pty;
  final _approvals = <int, Completer<bool>>{};

  /// From this share of the week's allowance on, the conversation says
  /// so, once.
  static const _warnAt = 0.8;
  bool _warned = false;

  /// What the user wrote instead of approving a proposal, passed on with
  /// the refusal.
  String? _steer;

  /// The user said [text]: an answer to the assistant's question if it
  /// asked one, else the next message of the conversation.
  Future<void> submit(String text) async {
    final answer = _answer;
    if (answer != null) {
      _answer = null;
      session.add(AssistantMessage(text));
      answer.complete(text);
      return;
    }
    if (_approvals.isNotEmpty) {
      session.add(AssistantMessage(text));
      _steer = text;
      for (final approval in _approvals.values) {
        approval.complete(false);
      }
      _approvals.clear();
      return;
    }
    if (session.busy) return;
    final run = ++_run;
    session.ask(text);
    if (_target == null) {
      final bound = await _bind();
      if (run != _run) return;
      if (!bound) {
        _fail(AssistantFailureKind.noConnection);
        return;
      }
    }
    final notes = _messages.isEmpty && memoryOn()
        ? await memory.notesFor(_target!.profileId)
        : const <String>[];
    final system = _messages.isEmpty ? _system : null;
    _appendUser([
      if (system != null) {'type': 'text', 'text': _redactor!.hide(system)},
      if (notes.isNotEmpty)
        {
          'type': 'text',
          'text': _redactor!.hide(
            'Notes saved about this server earlier:\n${notes.map((n) => '- $n').join('\n')}',
          ),
        },
      {'type': 'text', 'text': _redactor!.hide(text)},
    ]);
    await _loop(run);
  }

  void approve(int index) => _approvals.remove(index)?.complete(true);

  void skip(int index) => _approvals.remove(index)?.complete(false);

  /// Stops whatever runs. The conversation stays usable: tool calls left
  /// without a result get one saying the user stopped them.
  void stop() {
    _run++;
    transport.cancel();
    _pty?.close();
    _pty = null;
    _answer?.complete('');
    _answer = null;
    for (final approval in _approvals.values) {
      approval.complete(false);
    }
    _approvals.clear();
    if (session.busy || session.mood == AssistantMood.waiting) {
      session.setMood(AssistantMood.failed);
    }
  }

  /// Forgets the conversation and the server it was bound to.
  void reset() {
    stop();
    _messages.clear();
    _target = null;
    _redactor = null;
    _system = null;
    _warned = false;
  }

  Future<bool> _bind() async {
    final target = this.target();
    if (target == null) return false;
    _target = target;
    final names = await _runQuietly(
      'hostname; hostname -f 2>/dev/null',
      const Duration(seconds: 5),
    );
    final hosts = [
      ...target.hosts,
      if (names.exitCode == 0)
        ...names.output
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && line != 'localhost'),
    ];
    _redactor = AssistantRedactor(hosts: hosts, users: target.users);
    final system = await _runQuietly(
      target.windows ? kWindowsSystemProbe : kUnixSystemProbe,
      const Duration(seconds: 5),
    );
    _system = describeServerSystem(system.output, windows: target.windows);
    return true;
  }

  /// What the server is, for the model to pick its commands by; null when
  /// it could not be told.
  String? _system;

  Future<void> _loop(int run) async {
    for (var step = 0; step < maxSteps; step++) {
      session.setMood(AssistantMood.thinking);
      final builder = AssistantMessageBuilder();
      int? note;
      try {
        await for (final event in transport.step(
          _messages,
          memory: memoryOn(),
        )) {
          if (run != _run) return;
          builder.add(event);
          final text = builder.text.trim();
          if (text.isEmpty) continue;
          final shown = AssistantNote(_redactor!.reveal(text));
          if (note == null) {
            note = session.add(shown);
          } else {
            session.replace(note, shown);
          }
        }
      } on AssistantRequestError catch (error) {
        if (run == _run) _fail(_failureFor(error.code));
        return;
      } on Object {
        if (run == _run) _fail(AssistantFailureKind.provider);
        return;
      }
      if (run != _run) return;
      final used = transport.lastUsage;
      if (!_warned && used != null && used >= _warnAt) {
        _warned = true;
        session.add(AssistantUsageNotice(used));
      }
      if (!builder.done) {
        _fail(AssistantFailureKind.provider);
        return;
      }
      _messages.add(builder.message);
      final uses = builder.toolUses;
      if (uses.isEmpty || builder.stopReason != 'tool_use') {
        session.setMood(AssistantMood.done);
        return;
      }
      final results = <Map<String, dynamic>>[];
      for (final use in uses) {
        final id = use['id'] as String;
        if (run != _run) {
          results.add(_result(id, 'The user stopped this.', error: true));
          continue;
        }
        results.add(await _tool(run, use));
      }
      _appendUser(results);
      if (run != _run) return;
    }
    _fail(AssistantFailureKind.tooManySteps);
  }

  Future<Map<String, dynamic>> _tool(int run, Map<String, dynamic> use) async {
    final id = use['id'] as String;
    final input = (use['input'] as Map?)?.cast<String, dynamic>() ?? const {};
    String text(String key) => _redactor!.reveal('${input[key] ?? ''}');
    final malformed = _malformed(use['name'] as String?, input);
    if (malformed != null) {
      return _result(
        id,
        'Your ${use['name']} call was malformed: $malformed. Tool input is a JSON object; every value is plain text, with no tags or parameter markup inside. Call it again.',
        error: true,
      );
    }
    switch (use['name']) {
      case 'inspect':
        return _inspect(run, id, text('purpose'), text('command'));
      case 'read_file':
        final path = text('path');
        final lines = ((input['lines'] as num?)?.toInt() ?? 200).clamp(1, 2000);
        final command = 'tail -n $lines -- ${shellQuote(path)}';
        if (mayHoldSecrets(path)) {
          final index = session.add(
            AssistantProposal(
              why: path,
              commands: [command],
              kind: AssistantProposalKind.readSecret,
            ),
          );
          if (!await _approval(index)) {
            _settle(index, AssistantProposalState.skipped);
            return _result(
              id,
              _declined('The user did not let you read this file.'),
            );
          }
          _settle(index, AssistantProposalState.running);
          final output = await _runQuietly(command, _inspectTimeout);
          _settle(
            index,
            output.timedOut
                ? AssistantProposalState.failed
                : AssistantProposalState.done,
          );
          return _result(id, _report(output));
        }
        return _inspect(run, id, text('purpose'), command, checked: false);
      case 'propose':
        final commands = [
          for (final command in (input['commands'] as List? ?? const []))
            _redactor!.reveal('$command'),
        ];
        final index = session.add(
          AssistantProposal(why: text('why'), commands: commands),
        );
        if (!await _approval(index)) {
          _settle(index, AssistantProposalState.skipped);
          return _result(
            id,
            _declined('The user skipped these commands; nothing ran.'),
          );
        }
        final terminal = Terminal(maxLines: 2000);
        final proposal = session.steps[index] as AssistantProposal;
        session.replace(
          index,
          proposal.copyWith(
            state: AssistantProposalState.running,
            terminal: terminal,
          ),
        );
        session.setMood(AssistantMood.working);
        final reports = <String>[];
        var failed = false;
        for (final command in commands) {
          if (run != _run) break;
          final outcome = await _runInTerminal(terminal, command);
          reports.add('\$ $command\n${_report(outcome)}');
          if (outcome.timedOut || (outcome.exitCode ?? 1) != 0) {
            failed = true;
            break;
          }
        }
        terminal.onOutput = null;
        terminal.onResize = null;
        _settle(
          index,
          failed ? AssistantProposalState.failed : AssistantProposalState.done,
        );
        return _result(
          id,
          'The user approved. ${failed ? 'A command failed and the rest did not run.' : 'All commands ran.'}\n\n${reports.join('\n\n')}',
        );
      case 'read_screen':
        final index = session.add(
          const AssistantCheck(title: '', command: '', screen: true),
        );
        final screen = _target!.readScreen()?.trimRight() ?? '';
        session.replace(
          index,
          AssistantCheck(
            title: '',
            command: '',
            screen: true,
            status: AssistantStepStatus.done,
            output: screen.isEmpty ? null : _clip(screen),
          ),
        );
        return _result(
          id,
          screen.isEmpty ? 'The screen is empty.' : _clip(screen),
        );
      case 'remember':
        final note = text('note').trim();
        if (!memoryOn()) {
          return _result(id, 'Memory is off; nothing was saved.', error: true);
        }
        if (_redactor!.hide(note).contains('[SECRET_')) {
          return _result(
            id,
            'That looks like it holds a secret, so it was not saved.',
            error: true,
          );
        }
        if (await memory.add(_target!.profileId, note)) {
          session.add(AssistantRemembered(note));
        }
        return _result(id, 'Saved.');
      case 'ask_user':
        session.add(AssistantNote(text('question')));
        session.setMood(AssistantMood.waiting);
        final answer = Completer<String>();
        _answer = answer;
        final reply = await answer.future;
        if (run != _run) {
          return _result(id, 'The user stopped this.', error: true);
        }
        session.setMood(AssistantMood.thinking);
        return _result(id, reply);
      default:
        return _result(id, 'There is no such tool.', error: true);
    }
  }

  /// Runs [command] in [terminal], under a `$ command` line, with what the
  /// user types going to it. Returns what the command left on the screen -
  /// the rendered text, so colours and redrawn progress bars come out clean
  /// - and its exit code. A password typed into it is not echoed, so it is
  /// in neither.
  Future<AssistantRun> _runInTerminal(Terminal terminal, String command) async {
    terminal.write('\x1b[2m\$ $command\x1b[0m\r\n');
    final start = terminal.buffer.absoluteCursorY;
    final AssistantPty pty;
    try {
      pty = await _target!.shell.open(
        command,
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
      );
    } on Object catch (error) {
      terminal.write('$error\r\n');
      return (
        output: 'Could not run it: $error',
        exitCode: null,
        timedOut: false,
      );
    }
    _pty = pty;
    terminal.onOutput = (data) =>
        pty.write(Uint8List.fromList(utf8.encode(data)));
    terminal.onResize = (columns, rows, _, _) => pty.resize(columns, rows);
    final printed = utf8.decoder.bind(pty.output).listen(terminal.write);
    var timedOut = false;
    int? exitCode;
    try {
      exitCode = await pty.exitCode.timeout(_answerTimeout);
    } on TimeoutException {
      timedOut = true;
      pty.close();
    }
    await printed.cancel();
    _pty = null;
    terminal.write('\r\n');
    final buffer = terminal.buffer;
    final lines = [
      for (var line = start; line < buffer.height; line++)
        buffer.lines[line].getText().trimRight(),
    ];
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return (output: lines.join('\n'), exitCode: exitCode, timedOut: timedOut);
  }

  /// What is wrong with a tool call's [input], or null when it is sound.
  ///
  /// Models sometimes spill the markup of a tool call into its arguments -
  /// a `</why><parameter name="commands">` inside a reason, with the real
  /// list left empty. Such a call is sent back to the model rather than
  /// shown, so a broken proposal never reaches the user.
  static String? _malformed(String? name, Map<String, dynamic> input) {
    final markup = RegExp(
      r'</?(?:parameter|invoke|antml|function_calls)\b|</(?:why|command|commands|purpose|path|question|lines)>',
    );
    for (final value in input.values) {
      final texts = value is List ? value : [value];
      for (final text in texts) {
        if (text is String && markup.hasMatch(text)) {
          return 'it contains tool markup';
        }
      }
    }
    String? needText(String key) {
      final value = input[key];
      return value is String && value.trim().isNotEmpty
          ? null
          : '$key is missing';
    }

    switch (name) {
      case 'inspect':
        return needText('command') ?? needText('purpose');
      case 'read_file':
        return needText('path');
      case 'ask_user':
        return needText('question');
      case 'remember':
        return needText('note');
      case 'propose':
        final commands = input['commands'];
        if (commands is! List || commands.isEmpty || commands.length > 10) {
          return 'commands must be a list of one to ten commands';
        }
        if (commands.any((c) => c is! String || c.trim().isEmpty)) {
          return 'every command must be non-empty text';
        }
        return needText('why');
    }
    return null;
  }

  Future<Map<String, dynamic>> _inspect(
    int run,
    String id,
    String purpose,
    String command, {
    bool checked = true,
  }) async {
    final refusal = checked ? refuseInspect(command) : null;
    if (refusal != null && refuseAsking(command) == null) {
      return _askToCheck(run, id, purpose, command, refusal);
    }
    final index = session.add(AssistantCheck(title: purpose, command: command));
    if (refusal != null) {
      session.replace(
        index,
        AssistantCheck(
          title: purpose,
          command: command,
          status: AssistantStepStatus.failed,
          output: refusal,
        ),
      );
      return _result(
        id,
        'The device refused to run this: $refusal. Run something that ends on its own, on one line.',
        error: true,
      );
    }
    session.setMood(AssistantMood.working, activity: purpose);
    final output = await _runQuietly(command, _inspectTimeout);
    session.replace(
      index,
      AssistantCheck(
        title: purpose,
        command: command,
        status: output.timedOut
            ? AssistantStepStatus.failed
            : AssistantStepStatus.done,
        output: output.output.trim().isEmpty ? null : _clip(output.output),
      ),
    );
    return _result(id, _report(output));
  }

  /// A check the device could not tell only reads: the user is asked, as
  /// for a fix, and it runs in a terminal they can watch once they allow
  /// it. The model hears the output, or that the user said no.
  Future<Map<String, dynamic>> _askToCheck(
    int run,
    String id,
    String purpose,
    String command,
    String refusal,
  ) async {
    final index = session.add(
      AssistantProposal(
        why: purpose,
        commands: [command],
        kind: AssistantProposalKind.check,
        reason: refusal,
      ),
    );
    if (!await _approval(index)) {
      _settle(index, AssistantProposalState.skipped);
      return _result(
        id,
        _declined(
          'The device could not tell this only reads ($refusal), so it asked the user, who did not run it.',
        ),
      );
    }
    final terminal = Terminal(maxLines: 2000);
    final proposal = session.steps[index] as AssistantProposal;
    session.replace(
      index,
      proposal.copyWith(
        state: AssistantProposalState.running,
        terminal: terminal,
      ),
    );
    session.setMood(AssistantMood.working, activity: purpose);
    final outcome = await _runInTerminal(terminal, command);
    terminal.onOutput = null;
    terminal.onResize = null;
    if (run != _run) return _result(id, 'The user stopped this.', error: true);
    _settle(
      index,
      outcome.timedOut
          ? AssistantProposalState.failed
          : AssistantProposalState.done,
    );
    return _result(id, 'The user allowed it.\n${_report(outcome)}');
  }

  Future<AssistantRun> _runQuietly(String command, Duration timeout) async {
    try {
      return await _target!.shell.run(command, timeout: timeout);
    } on Object catch (error) {
      return (
        output: 'Could not run it: $error',
        exitCode: null,
        timedOut: false,
      );
    }
  }

  Future<bool> _approval(int index) {
    session.setMood(AssistantMood.waiting);
    final approval = Completer<bool>();
    _approvals[index] = approval;
    return approval.future;
  }

  /// [refusal], with what the user wrote instead, if they wrote something.
  String _declined(String refusal) {
    final said = _steer;
    _steer = null;
    return said == null ? refusal : '$refusal They said instead: $said';
  }

  void _settle(int index, AssistantProposalState state) {
    final step = session.steps[index];
    if (step is AssistantProposal) {
      session.replace(index, step.copyWith(state: state));
    }
  }

  String _report(AssistantRun run) {
    final head = run.timedOut
        ? 'timed out'
        : 'exit code ${run.exitCode ?? 'unknown'}';
    final output = _clip(run.output).trim();
    return output.isEmpty ? '$head, no output' : '$head\n$output';
  }

  static String _clip(String output) {
    var lines = output.split('\n');
    if (lines.length > _keepLines) {
      lines = [
        '[${lines.length - _keepLines} earlier lines cut]',
        ...lines.sublist(lines.length - _keepLines),
      ];
    }
    var text = lines.join('\n');
    if (text.length > _keepChars) {
      text = '[cut]${text.substring(text.length - _keepChars)}';
    }
    return text;
  }

  Map<String, dynamic> _result(String id, String text, {bool error = false}) =>
      {
        'type': 'tool_result',
        'tool_use_id': id,
        'content': _redactor!.hide(text.isEmpty ? '(empty)' : text),
        if (error) 'is_error': true,
      };

  /// Adds [blocks] as the user's turn, joining them to the last message if
  /// that is already the user's - after a stop, say - so turns keep
  /// alternating.
  void _appendUser(List<Map<String, dynamic>> blocks) {
    if (_messages.isNotEmpty && _messages.last['role'] == 'user') {
      final content = _messages.last['content'];
      _messages.last['content'] = [
        if (content is List)
          ...content
        else
          {'type': 'text', 'text': '$content'},
        ...blocks,
      ];
      return;
    }
    _messages.add({'role': 'user', 'content': blocks});
  }

  void _fail(AssistantFailureKind kind) {
    session.add(AssistantFailure(kind));
    session.setMood(AssistantMood.failed);
  }

  static AssistantFailureKind _failureFor(String code) => switch (code) {
    'signed_out' ||
    'unauthorized' ||
    'token_expired' => AssistantFailureKind.signedOut,
    'pro_required' => AssistantFailureKind.proRequired,
    'not_allowed' => AssistantFailureKind.notAllowed,
    'rate_limited' || 'busy' => AssistantFailureKind.rateLimited,
    'budget_spent' => AssistantFailureKind.budgetSpent,
    'network' => AssistantFailureKind.network,
    _ => AssistantFailureKind.provider,
  };
}
