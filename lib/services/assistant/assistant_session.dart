import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:terminal_view/terminal_view.dart';

/// What the assistant is doing, which its orb shows by how it moves and in
/// which colour.
enum AssistantMood {
  /// Waiting for a task: a slow ring.
  idle,

  /// Asking the model: the ring spins fast and its characters churn.
  thinking,

  /// Running a command on the server: rings ripple out from the middle.
  working,

  /// Needs the user - an approval or an answer: a slow amber pulse.
  waiting,

  /// Finished the task: a calm green ring.
  done,

  /// Gave up or hit an error: a still red ring.
  failed,
}

/// Where a step the assistant took stands.
enum AssistantStepStatus { running, done, failed }

/// Where a fix the assistant proposed stands.
enum AssistantProposalState { pending, running, done, failed, skipped }

/// What a proposal asks the user to allow.
enum AssistantProposalKind {
  /// Commands that change the server, in the assistant's words.
  change,

  /// Reading a file that may hold secrets; [AssistantProposal.why] is its
  /// path.
  readSecret,

  /// A check the device could not tell only reads, so it runs once the
  /// user allows it; [AssistantProposal.reason] says why.
  check,
}

/// Why the assistant could not go on.
enum AssistantFailureKind {
  signedOut,
  proRequired,
  notAllowed,
  rateLimited,
  budgetSpent,
  network,
  provider,
  noConnection,
  tooManySteps,
}

/// One entry in the assistant's account of a task.
sealed class AssistantStep {
  const AssistantStep();
}

/// Something the user said.
class AssistantMessage extends AssistantStep {
  const AssistantMessage(this.text);

  final String text;
}

/// A look around the server: a read-only [command], what the assistant
/// meant to learn from it ([title]) and the end of its [output].
class AssistantCheck extends AssistantStep {
  const AssistantCheck({
    required this.title,
    required this.command,
    this.status = AssistantStepStatus.running,
    this.output,
    this.screen = false,
  });

  final String title;
  final String command;
  final AssistantStepStatus status;
  final String? output;

  /// A look at the user's terminal screen rather than a command; [title]
  /// and [command] are empty and the panel names it in the app's words.
  final bool screen;

  AssistantCheck copyWith({AssistantStepStatus? status, String? output}) =>
      AssistantCheck(
        title: title,
        command: command,
        status: status ?? this.status,
        output: output ?? this.output,
        screen: screen,
      );
}

/// The account has used most of this week's allowance; [used] is the
/// share, from 0 to 1.
class AssistantUsageNotice extends AssistantStep {
  const AssistantUsageNotice(this.used);

  final double used;
}

/// A note the assistant saved about the server, shown so it never
/// remembers anything behind the user's back.
class AssistantRemembered extends AssistantStep {
  const AssistantRemembered(this.note);

  final String note;
}

/// What the assistant says or concluded, in its own words.
class AssistantNote extends AssistantStep {
  const AssistantNote(this.text);

  final String text;
}

/// A change the assistant wants to make, which runs only once the user
/// approves it: [commands] and [why] they fix the problem.
class AssistantProposal extends AssistantStep {
  const AssistantProposal({
    required this.why,
    required this.commands,
    this.state = AssistantProposalState.pending,
    this.kind = AssistantProposalKind.change,
    this.terminal,
    this.reason,
  });

  final String why;
  final List<String> commands;
  final AssistantProposalState state;
  final AssistantProposalKind kind;

  /// Where the approved commands run, for the user to watch and answer
  /// them; null until they do.
  final Terminal? terminal;

  /// For a [AssistantProposalKind.check], what kept the device from running
  /// it on its own.
  final String? reason;

  AssistantProposal copyWith({
    AssistantProposalState? state,
    Terminal? terminal,
  }) => AssistantProposal(
    why: why,
    commands: commands,
    state: state ?? this.state,
    kind: kind,
    terminal: terminal ?? this.terminal,
    reason: reason,
  );
}

/// The assistant stopped for a reason the user should know, shown in the
/// app's words rather than the model's.
class AssistantFailure extends AssistantStep {
  const AssistantFailure(this.kind);

  final AssistantFailureKind kind;
}

/// How a task ended, said once at its end.
class AssistantSummary extends AssistantStep {
  const AssistantSummary(this.text, {this.solved = true});

  final String text;
  final bool solved;
}

/// A conversation with the assistant and everything it did in it: the state
/// the panel draws, as a chat - the user's messages, and after each the
/// checks, notes, proposals and summary the assistant answers with.
/// Whoever drives the assistant - the model loop, or a script in a demo -
/// appends and updates steps here; the panel only reads it and reports the
/// user's answers through the callbacks it is given.
class AssistantSession extends ChangeNotifier {
  AssistantSession({this.settleAfter = const Duration(seconds: 3)});

  /// How long a finished or stopped turn keeps its colour before the
  /// assistant goes back to rest.
  final Duration settleAfter;

  AssistantMood _mood = AssistantMood.idle;
  String? _activity;
  final List<AssistantStep> _steps = [];
  Timer? _settle;
  bool _disposed = false;

  AssistantMood get mood => _mood;

  /// What the assistant is doing this moment, for the line under its name.
  /// Null falls back to a line for [mood].
  String? get activity => _activity;

  List<AssistantStep> get steps => List.unmodifiable(_steps);

  /// Whether nothing has been said yet.
  bool get isEmpty => _steps.isEmpty;

  /// Whether the assistant is busy, so the panel offers Stop and holds the
  /// next message back.
  bool get busy =>
      _mood == AssistantMood.thinking || _mood == AssistantMood.working;

  /// The user said [text]: it joins the conversation and the assistant
  /// starts thinking about it.
  void ask(String text) {
    _steps.add(AssistantMessage(text));
    setMood(AssistantMood.thinking);
  }

  /// [AssistantMood.done] and [AssistantMood.failed] last [settleAfter],
  /// then the assistant is back at rest.
  void setMood(AssistantMood mood, {String? activity}) {
    _settle?.cancel();
    _mood = mood;
    _activity = activity;
    if (mood == AssistantMood.done || mood == AssistantMood.failed) {
      _settle = Timer(settleAfter, () {
        if (_disposed) return;
        _mood = AssistantMood.idle;
        _activity = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Appends [step] and returns its index, for [replace] later.
  int add(AssistantStep step) {
    _steps.add(step);
    notifyListeners();
    return _steps.length - 1;
  }

  void replace(int index, AssistantStep step) {
    _steps[index] = step;
    notifyListeners();
  }

  /// Forgets the conversation.
  void reset() {
    _settle?.cancel();
    _steps.clear();
    _mood = AssistantMood.idle;
    _activity = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _settle?.cancel();
    super.dispose();
  }
}
