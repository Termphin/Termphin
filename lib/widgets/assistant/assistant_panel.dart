import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:terminal_view/terminal_view.dart';

import '../../i18n/strings.g.dart';
import '../../services/assistant/assistant_session.dart';
import '../../services/settings/terminal_settings.dart';
import '../../theme/theme.dart';
import '../ui/app_badge.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/tag_chip.dart';
import 'assistant_markdown.dart';
import 'assistant_orb.dart';

/// What the panel reports back to whoever drives the assistant.
class AssistantActions {
  const AssistantActions({
    required this.onSubmit,
    required this.onApprove,
    required this.onSkip,
    required this.onStop,
    this.onEdit,
    this.onNewChat,
  });

  /// A new task, or a follow-up to the one on screen.
  final ValueChanged<String> onSubmit;

  /// The user approved the proposal at this index of the session's steps.
  final ValueChanged<int> onApprove;

  /// The user turned down the proposal at this index.
  final ValueChanged<int> onSkip;

  /// The user wants to change the proposal at this index before it runs.
  final ValueChanged<int>? onEdit;

  final VoidCallback onStop;

  /// The user started over; whoever drives the assistant forgets the
  /// conversation.
  final VoidCallback? onNewChat;
}

/// The assistant: before a task, its orb large with an invitation and a few
/// suggestions; once given one, the orb shrinks into a header over the
/// account of what it does - the checks it runs, what it concludes, the fix
/// it proposes for the user to approve, and how it ended - with a field for
/// the next task at the bottom. Fills whatever holds it.
class AssistantPanel extends StatefulWidget {
  const AssistantPanel({
    super.key,
    required this.session,
    required this.actions,
    this.controls,
  });

  final AssistantSession session;
  final AssistantActions actions;

  /// The holder's own buttons - minimise, close - at the top right.
  final Widget? controls;

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _scroll = ScrollController();
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _seen = widget.session.steps.length;
    widget.session.addListener(_followNewSteps);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_followNewSteps);
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the newest step in view as they arrive, and opens on it when
  /// the panel comes back to a task already under way.
  void _followNewSteps() {
    final count = widget.session.steps.length;
    if (count <= _seen) {
      _seen = count;
      return;
    }
    _seen = count;
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd(2));
  }

  /// Scrolls to the end, and once there checks it still is: a step that
  /// grows as it appears - a proposal and its buttons - adds height after
  /// the first measure, which would leave its bottom under the edge.
  Future<void> _toEnd(int tries) async {
    if (!mounted || !_scroll.hasClients) return;
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: AppTheme.motionMedium,
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !_scroll.hasClients || tries <= 1) return;
    await Future<void>.delayed(AppTheme.motionPage);
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 1) {
      await _toEnd(tries - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final session = widget.session;
        return Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: AppTheme.motionPage,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: session.isEmpty
                    ? _Intro(
                        key: const ValueKey('assistantIntro'),
                        onPick: widget.actions.onSubmit,
                        controls: widget.controls,
                      )
                    : _Task(
                        key: const ValueKey('assistantTask'),
                        session: session,
                        actions: widget.actions,
                        scroll: _scroll,
                        controls: widget.controls,
                      ),
              ),
            ),
            _Composer(
              started: !session.isEmpty,
              busy: session.busy,
              onSubmit: widget.actions.onSubmit,
              onStop: widget.actions.onStop,
            ),
          ],
        );
      },
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({super.key, required this.onPick, this.controls});

  final ValueChanged<String> onPick;
  final Widget? controls;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    final colors = context.colors;
    final body = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space24,
        vertical: AppTheme.space16,
      ),
      child: Column(
        children: [
          const SizedBox(height: AppTheme.space8),
          const AssistantOrb(size: AppTheme.assistantOrbLarge),
          const SizedBox(height: AppTheme.space12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.title,
                style: TextStyle(
                  fontSize: AppTheme.font20,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              AppBadge(t.beta, tone: BadgeTone.highlight),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            t.intro,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTheme.font14,
              height: 1.45,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.space16),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            alignment: WrapAlignment.center,
            children: [
              for (final suggestion in [
                t.suggestDown,
                t.suggestDisk,
                t.suggestHealth,
              ])
                TagChip(
                  label: suggestion,
                  selected: false,
                  onTap: () => onPick(suggestion),
                ),
            ],
          ),
        ],
      ),
    );
    final controls = this.controls;
    if (controls == null) return body;
    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          top: AppTheme.space4,
          right: AppTheme.space4,
          child: controls,
        ),
      ],
    );
  }
}

class _Task extends StatelessWidget {
  const _Task({
    super.key,
    required this.session,
    required this.actions,
    required this.scroll,
    this.controls,
  });

  final AssistantSession session;
  final AssistantActions actions;
  final ScrollController scroll;
  final Widget? controls;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    final colors = context.colors;
    final steps = session.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space16,
            AppTheme.space4,
            AppTheme.space12,
            AppTheme.space12,
          ),
          child: Row(
            children: [
              AssistantOrb(
                size: AppTheme.assistantOrbSmall,
                mood: session.mood,
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          t.title,
                          style: TextStyle(
                            fontSize: AppTheme.font15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: AppTheme.space6),
                        AppBadge(t.beta, tone: BadgeTone.highlight),
                      ],
                    ),
                    const SizedBox(height: AppTheme.space2),
                    AnimatedSwitcher(
                      duration: AppTheme.motionPage,
                      switchInCurve: _secondHalf,
                      switchOutCurve: _secondHalf,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, ?current],
                      ),
                      child: Text(
                        assistantStatus(t, session),
                        key: ValueKey(assistantStatus(t, session)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTheme.font12,
                          color: assistantMoodColor(context, session.mood),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ?controls,
            ],
          ),
        ),
        const AppDivider(),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space16,
              AppTheme.space16,
              AppTheme.space16,
              AppTheme.space24,
            ),
            itemCount: steps.length,
            itemBuilder: (context, index) => _Appear(
              key: ValueKey('step$index'),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: index + 1 < steps.length
                      ? _gapAfter(steps[index], steps[index + 1])
                      : 0,
                ),
                child: switch (steps[index]) {
                  final AssistantMessage message => _MessageBubble(
                    message: message,
                  ),
                  final AssistantCheck check => _ToolCall(check: check),
                  final AssistantNote note => _NoteTile(note: note),
                  final AssistantProposal proposal => _ProposalCard(
                    proposal: proposal,
                    onApprove: () => actions.onApprove(index),
                    onSkip: () => actions.onSkip(index),
                    onEdit: actions.onEdit == null
                        ? null
                        : () => actions.onEdit!(index),
                  ),
                  final AssistantSummary summary => _Summary(summary: summary),
                  final AssistantFailure failure => _Failure(failure: failure),
                  final AssistantRemembered remembered => _Remembered(
                    note: remembered.note,
                  ),
                  final AssistantUsageNotice notice => _UsageNotice(
                    used: notice.used,
                  ),
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tool calls in a row sit close, as one block of work; anything else gets
/// room, and a new message from the user the most.
double _gapAfter(AssistantStep step, AssistantStep next) {
  if (step is AssistantCheck && next is AssistantCheck) return AppTheme.space6;
  if (next is AssistantMessage) return AppTheme.space24;
  return AppTheme.space12;
}

/// Lets a cross-fade finish fading the old child out before the new one
/// fades in, so two lines of different text never show on top of each
/// other.
const _secondHalf = Interval(0.5, 1, curve: Curves.easeOut);

/// The line saying what the assistant is doing: its own words for this
/// moment when it gave some, else a word for its mood.
String assistantStatus(Translations$assistant$en t, AssistantSession session) =>
    session.activity ??
    switch (session.mood) {
      AssistantMood.idle => t.statusIdle,
      AssistantMood.thinking => t.statusThinking,
      AssistantMood.working => t.statusWorking,
      AssistantMood.waiting => t.statusWaiting,
      AssistantMood.done => t.statusDone,
      AssistantMood.failed => t.statusFailed,
    };

/// The colour of [assistantStatus]: plain while it works, the state's own
/// colour once it waits, finishes or fails.
Color assistantMoodColor(BuildContext context, AssistantMood mood) {
  final colors = context.colors;
  return switch (mood) {
    AssistantMood.waiting => colors.warning,
    AssistantMood.done => colors.success,
    AssistantMood.failed => colors.error,
    _ => colors.textSecondary,
  };
}

/// Fades and lifts a step in the first time it is built.
class _Appear extends StatelessWidget {
  const _Appear({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppTheme.motionPage,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * AppTheme.space12),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// One tool call: a slim box with the step's state, what it was for and,
/// folded, the command it ran. A tap unfolds the whole command and the end
/// of its output, and folds them away again.
class _ToolCall extends StatefulWidget {
  const _ToolCall({required this.check});

  final AssistantCheck check;

  @override
  State<_ToolCall> createState() => _ToolCallState();
}

class _ToolCallState extends State<_ToolCall> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final check = widget.check;
    final output = check.output;
    return Container(
      decoration: BoxDecoration(
        color: colors.isDark ? colors.surfaceOffset : colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: colors.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => setState(() => _open = !_open),
          child: AnimatedSize(
            duration: AppTheme.motionMedium,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space12,
                vertical: AppTheme.space10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StepState(status: check.status),
                      const SizedBox(width: AppTheme.space10),
                      Expanded(
                        child: Text(
                          check.screen
                              ? Translations.of(context).assistant.readScreen
                              : check.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTheme.font13,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: AppTheme.motionMedium,
                        child: Icon(
                          PhosphorIconsRegular.caretDown,
                          size: AppTheme.icon14,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  if (check.command.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.space4),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppTheme.icon16 + AppTheme.space10,
                      ),
                      child: Text(
                        check.command,
                        maxLines: _open ? null : 1,
                        overflow: _open ? null : TextOverflow.ellipsis,
                        style: colors.monoStyle.copyWith(
                          fontSize: AppTheme.font11,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                  if (_open && output != null) ...[
                    const SizedBox(height: AppTheme.space8),
                    _CodeBox(text: output, tone: _CodeTone.output),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a tool call stands: a small spinner while it runs, then a tick or
/// a cross.
class _StepState extends StatelessWidget {
  const _StepState({required this.status});

  final AssistantStepStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox.square(
      dimension: AppTheme.icon16,
      child: AnimatedSwitcher(
        duration: AppTheme.motionMedium,
        child: switch (status) {
          AssistantStepStatus.running => Padding(
            key: const ValueKey('running'),
            padding: const EdgeInsets.all(AppTheme.space2),
            child: CircularProgressIndicator(
              strokeWidth: AppTheme.strokeWide,
              color: colors.primary,
            ),
          ),
          AssistantStepStatus.done => Icon(
            PhosphorIconsRegular.checkCircle,
            key: const ValueKey('done'),
            size: AppTheme.icon16,
            color: colors.success,
          ),
          AssistantStepStatus.failed => Icon(
            PhosphorIconsRegular.xCircle,
            key: const ValueKey('failed'),
            size: AppTheme.icon16,
            color: colors.error,
          ),
        },
      ),
    );
  }
}

/// Something the user said, on the right like any chat.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.82,
        alignment: Alignment.centerRight,
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space14,
              vertical: AppTheme.space10,
            ),
            decoration: BoxDecoration(
              color: colors.primaryHighlight,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMd),
                topRight: Radius.circular(AppTheme.radiusMd),
                bottomLeft: Radius.circular(AppTheme.radiusMd),
                bottomRight: Radius.circular(AppTheme.radiusXs),
              ),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: AppTheme.font14,
                height: 1.4,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the assistant says, as plain text like any chat reply.
class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});

  final AssistantNote note;

  @override
  Widget build(BuildContext context) => AssistantMarkdown(note.text);
}

enum _CodeTone { output, command }

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.text, required this.tone});

  final String text;
  final _CodeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space10,
        vertical: AppTheme.space8,
      ),
      decoration: BoxDecoration(
        color: colors.isDark ? colors.backgroundPrimary : colors.surfaceOffset,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Text(
        text,
        softWrap: tone == _CodeTone.command,
        style: colors.monoStyle.copyWith(
          fontSize: tone == _CodeTone.command
              ? AppTheme.font12
              : AppTheme.font11,
          height: 1.45,
          color: tone == _CodeTone.command
              ? colors.textPrimary
              : colors.textSecondary,
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.onApprove,
    required this.onSkip,
    this.onEdit,
  });

  final AssistantProposal proposal;
  final VoidCallback onApprove;
  final VoidCallback onSkip;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    final colors = context.colors;
    final secret = proposal.kind == AssistantProposalKind.readSecret;
    final check = proposal.kind == AssistantProposalKind.check;
    return AppCard(
      elevated: true,
      padding: const EdgeInsets.all(AppTheme.space14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  secret
                      ? t.readSecretTitle
                      : check
                      ? t.checkTitle
                      : t.proposalTitle,
                  style: TextStyle(
                    fontSize: AppTheme.font15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (!secret && !check)
                AppBadge(t.changesServer, tone: BadgeTone.warning),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            secret
                ? t.readSecretWhy(path: proposal.why)
                : check
                ? t.checkWhy(
                    purpose: proposal.why,
                    reason: proposal.reason ?? '',
                  )
                : proposal.why,
            style: TextStyle(
              fontSize: AppTheme.font13,
              height: 1.45,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.space10),
          if (proposal.terminal case final terminal?)
            _MiniTerminal(
              terminal: terminal,
              live: proposal.state == AssistantProposalState.running,
            )
          else
            _CodeBox(
              text: proposal.commands.map((c) => '\$ $c').join('\n'),
              tone: _CodeTone.command,
            ),
          const SizedBox(height: AppTheme.space12),
          AnimatedSwitcher(
            duration: AppTheme.motionPage,
            switchInCurve: _secondHalf,
            switchOutCurve: _secondHalf,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: switch (proposal.state) {
              AssistantProposalState.pending => Row(
                key: const ValueKey('pending'),
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onSkip, child: Text(t.skip)),
                  if (onEdit != null) ...[
                    const SizedBox(width: AppTheme.space4),
                    OutlinedButton(onPressed: onEdit, child: Text(t.edit)),
                  ],
                  const SizedBox(width: AppTheme.space8),
                  FilledButton.icon(
                    onPressed: proposal.commands.isEmpty ? null : onApprove,
                    icon: const Icon(
                      PhosphorIconsFill.play,
                      size: AppTheme.icon14,
                    ),
                    label: Text(secret ? t.allow : t.run),
                  ),
                ],
              ),
              AssistantProposalState.running => Row(
                key: const ValueKey('running'),
                children: [
                  SizedBox.square(
                    dimension: AppTheme.icon14,
                    child: CircularProgressIndicator(
                      strokeWidth: AppTheme.strokeWide,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Text(
                    t.proposalRunning,
                    style: TextStyle(
                      fontSize: AppTheme.font13,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              AssistantProposalState.done => Align(
                key: const ValueKey('done'),
                alignment: Alignment.centerLeft,
                child: AppBadge(t.proposalDone, tone: BadgeTone.success),
              ),
              AssistantProposalState.failed => Align(
                key: const ValueKey('failed'),
                alignment: Alignment.centerLeft,
                child: AppBadge(t.proposalFailed, tone: BadgeTone.error),
              ),
              AssistantProposalState.skipped => Align(
                key: const ValueKey('skipped'),
                alignment: Alignment.centerLeft,
                child: AppBadge(t.proposalSkipped, tone: BadgeTone.neutral),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// How a task ended: the outcome as a badge, then the assistant's account
/// of it as plain text.
class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final AssistantSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppBadge(
          summary.solved ? t.solved : t.unsolved,
          tone: summary.solved ? BadgeTone.success : BadgeTone.warning,
        ),
        const SizedBox(height: AppTheme.space8),
        AssistantMarkdown(summary.text),
      ],
    );
  }
}

/// Where approved commands run: a small terminal in the session's colours
/// and font. While they run, a tap gives it the keyboard so the user can
/// answer a question or type a password; afterwards it only shows what
/// happened.
class _MiniTerminal extends StatefulWidget {
  const _MiniTerminal({required this.terminal, required this.live});

  final Terminal terminal;
  final bool live;

  @override
  State<_MiniTerminal> createState() => _MiniTerminalState();
}

class _MiniTerminalState extends State<_MiniTerminal> {
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_MiniTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.live && !widget.live) _focus.unfocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.terminalSchemeForId(terminalSettings.scheme.value);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      child: SizedBox(
        height: AppTheme.assistantTerminalHeight,
        child: ColoredBox(
          color: scheme.background,
          child: TerminalView(
            widget.terminal,
            focusNode: _focus,
            autofocus: false,
            readOnly: !widget.live,
            theme: TerminalTheme(
              cursor: scheme.cursor,
              selection: scheme.selection,
              foreground: scheme.foreground,
              background: scheme.background,
              black: scheme.black,
              red: scheme.red,
              green: scheme.green,
              yellow: scheme.yellow,
              blue: scheme.blue,
              magenta: scheme.magenta,
              cyan: scheme.cyan,
              white: scheme.white,
              brightBlack: scheme.brightBlack,
              brightRed: scheme.brightRed,
              brightGreen: scheme.brightGreen,
              brightYellow: scheme.brightYellow,
              brightBlue: scheme.brightBlue,
              brightMagenta: scheme.brightMagenta,
              brightCyan: scheme.brightCyan,
              brightWhite: scheme.brightWhite,
              searchHitBackground: scheme.selection,
              searchHitBackgroundCurrent: scheme.cursor,
              searchHitForeground: scheme.background,
            ),
            textScaler: AppTheme.terminalTextScaler(context),
            textStyle: TerminalStyle(
              fontSize: AppTheme.font12,
              fontFamily: terminalSettings.fontFamily.value,
              fontFamilyFallback: const ['Roboto Mono', 'monospace'],
            ),
            padding: const EdgeInsets.all(AppTheme.space8),
            hardwareKeyboardOnly: false,
          ),
        ),
      ),
    );
  }
}

/// A note the assistant saved about the server, said in the chat so it
/// never remembers anything unseen.
class _Remembered extends StatelessWidget {
  const _Remembered({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          PhosphorIconsRegular.bookmarkSimple,
          size: AppTheme.icon16,
          color: colors.primary,
        ),
        const SizedBox(width: AppTheme.space8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${t.remembered}: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
                TextSpan(text: note),
              ],
            ),
            style: TextStyle(
              fontSize: AppTheme.font13,
              height: 1.45,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Most of this week's allowance is used: said once in a conversation,
/// so the limit never comes as a surprise.
class _UsageNotice extends StatelessWidget {
  const _UsageNotice({required this.used});

  final double used;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    final colors = context.colors;
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final renews = today
        .add(Duration(days: 7 - (now.weekday - DateTime.monday)))
        .toLocal();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          PhosphorIconsRegular.gauge,
          size: AppTheme.icon16,
          color: colors.warning,
        ),
        const SizedBox(width: AppTheme.space8),
        Expanded(
          child: Text(
            t.usageNotice(
              percent: (used * 100).round(),
              date: DateFormat.MMMd().format(renews),
            ),
            style: TextStyle(
              fontSize: AppTheme.font13,
              height: 1.45,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Why the assistant stopped, in the app's words, in the warning colour.
class _Failure extends StatelessWidget {
  const _Failure({required this.failure});

  final AssistantFailure failure;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    final colors = context.colors;
    final text = switch (failure.kind) {
      AssistantFailureKind.signedOut => t.failSignedOut,
      AssistantFailureKind.proRequired => t.failPro,
      AssistantFailureKind.notAllowed => t.failNotAllowed,
      AssistantFailureKind.rateLimited => t.failRate,
      AssistantFailureKind.budgetSpent => t.failBudget,
      AssistantFailureKind.network => t.failNetwork,
      AssistantFailureKind.provider => t.failProvider,
      AssistantFailureKind.noConnection => t.failNoConnection,
      AssistantFailureKind.tooManySteps => t.failTooManySteps,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          PhosphorIconsFill.warningCircle,
          size: AppTheme.icon16,
          color: colors.warning,
        ),
        const SizedBox(width: AppTheme.space8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: AppTheme.font14,
              height: 1.45,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The message field. While the assistant works its send button turns into
/// a stop button, where the thumb already is.
class _Composer extends StatefulWidget {
  const _Composer({
    required this.started,
    required this.busy,
    required this.onSubmit,
    required this.onStop,
  });

  final bool started;
  final bool busy;
  final ValueChanged<String> onSubmit;
  final VoidCallback onStop;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.busy) return;
    _controller.clear();
    widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space12,
        AppTheme.space8,
        AppTheme.space12,
        AppTheme.space12,
      ),
      child: Container(
        decoration: colors.fieldDecoration,
        padding: const EdgeInsets.only(
          left: AppTheme.space16,
          right: AppTheme.space6,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !widget.busy,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                style: TextStyle(
                  fontSize: AppTheme.font15,
                  color: colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: widget.started ? t.followUp : t.placeholder,
                  hintStyle: TextStyle(
                    fontSize: AppTheme.font14,
                    color: colors.textTertiary,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppTheme.space12,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: AppTheme.motionMedium,
              child: widget.busy
                  ? IconButton.filled(
                      key: const ValueKey('stop'),
                      tooltip: t.stop,
                      onPressed: widget.onStop,
                      icon: const Icon(
                        PhosphorIconsFill.stop,
                        size: AppTheme.icon16,
                      ),
                    )
                  : IconButton.filled(
                      key: const ValueKey('send'),
                      tooltip: t.send,
                      onPressed: _send,
                      icon: const Icon(
                        PhosphorIconsFill.arrowUp,
                        size: AppTheme.icon18,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
