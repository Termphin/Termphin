import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/assistant/assistant_session.dart';
import '../../theme/theme.dart';
import 'assistant_orb.dart';
import 'assistant_panel.dart';

/// The assistant over the terminal, filling the `Stack` it is put in
/// without taking any touch outside itself.
///
/// Minimised it is its orb in the bottom right corner, a button that opens
/// it; while the assistant works or waits for the user the orb grows into a
/// pill that says so, in the colour of its mood, so the terminal stays
/// usable and a "Needs your OK" is still seen. Once a turn is over the pill
/// folds back into the orb. Opened, the same shape grows
/// from the corner into a window over the terminal - the panel with
/// minimise and close at its top - and shrinks back into the corner when
/// minimised. Put it over the whole screen: the window covers the toolbar
/// too, and since the screen already shrinks above the keyboard, it stays
/// in sight while the user types into it. A new chat clears the
/// conversation.
class AssistantOverlay extends StatefulWidget {
  const AssistantOverlay({
    super.key,
    required this.session,
    required this.actions,
    this.bubbleClearance,
    this.hintKey,
    this.makeRoom,
  });

  final AssistantSession session;
  final AssistantActions actions;

  /// Height kept clear under the minimised orb - the special-keys toolbar
  /// and anything else along the bottom it should not cover. The window
  /// opens over all of it.
  final ValueListenable<double>? bubbleClearance;

  /// What the overlay is shown for - the connected session. The first time
  /// it sees a key it says "Ask Phin" for a moment before tucking away, so
  /// the user learns the assistant is there.
  final String? hintKey;

  /// While true, the minimised assistant slides off the screen entirely -
  /// something else needs its corner, such as the terminal's
  /// scroll-to-bottom button. An open window stays.
  final ValueListenable<bool>? makeRoom;

  @override
  State<AssistantOverlay> createState() => AssistantOverlayState();
}

/// Open or minimised; [open] and [minimize] are there for whoever wants to
/// do either from outside, such as a shortcut.
///
/// Minimised and at rest, the orb tucks itself behind the right edge with
/// only a sliver showing, so it covers as little of the terminal as it can.
/// A tap on the sliver brings it out, a tap on the orb opens the window, and
/// left alone it tucks itself away again after [_tuckAfter].
class AssistantOverlayState extends State<AssistantOverlay> {
  static const _tuckAfter = Duration(seconds: 4);

  bool _open = false;
  bool _shown = false;
  bool _hint = false;
  Timer? _tuck;
  final _hinted = <String>{};

  bool get isOpen => _open;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    _hintFor(widget.hintKey);
  }

  /// Says "Ask Phin" for [key] once, then tucks away.
  void _hintFor(String? key) {
    if (key == null || !_hinted.add(key) || _open) return;
    _hint = true;
    _shown = true;
    _tuck?.cancel();
    _tuck = Timer(_tuckAfter, () {
      if (!mounted) return;
      setState(() {
        _hint = false;
        if (!_open && !_working) _shown = false;
      });
    });
  }

  @override
  void didUpdateWidget(AssistantOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_onSession);
      widget.session.addListener(_onSession);
    }
    if (oldWidget.hintKey != widget.hintKey) _hintFor(widget.hintKey);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _tuck?.cancel();
    super.dispose();
  }

  bool get _working =>
      widget.session.busy || widget.session.mood == AssistantMood.waiting;

  /// A turn that ends while minimised leaves the orb out for a moment
  /// before it tucks away.
  void _onSession() {
    if (_open) return;
    if (_working) {
      _tuck?.cancel();
      _shown = true;
    } else if (_tuck?.isActive != true) {
      _tuckLater();
    }
  }

  void _tuckLater() {
    _tuck?.cancel();
    _tuck = Timer(_tuckAfter, () {
      if (!mounted || _open || _working) return;
      setState(() {
        _hint = false;
        _shown = false;
      });
    });
  }

  void open() {
    _tuck?.cancel();
    setState(() {
      _open = true;
      _hint = false;
    });
  }

  void minimize() {
    setState(() {
      _open = false;
      _shown = true;
    });
    if (!_working) _tuckLater();
  }

  void _bring() {
    setState(() => _shown = true);
    _tuckLater();
  }

  /// How wide the pill has to be for the orb and [text] beside it.
  static double _pillWidth(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _Bubble.textStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return AppTheme.assistantBubble +
        width +
        AppTheme.space16 +
        AppTheme.space2;
  }

  /// Starts over: stops whatever runs and clears the conversation, leaving
  /// the window open on a fresh one.
  void _newChat() {
    if (widget.session.busy) widget.actions.onStop();
    widget.actions.onNewChat?.call();
    widget.session.reset();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    return LayoutBuilder(
      builder: (context, constraints) => ListenableBuilder(
        listenable: Listenable.merge([
          widget.session,
          ?widget.bubbleClearance,
          ?widget.makeRoom,
        ]),
        builder: (context, _) {
          final session = widget.session;
          final area = constraints.biggest;
          const margin = AppTheme.space12;
          const bubble = AppTheme.assistantBubble;
          final clearance = widget.bubbleClearance?.value ?? 0;
          final working = session.busy || session.mood == AssistantMood.waiting;
          final pill = working || (_hint && !_open);
          final bubbleWidth = pill
              ? min(
                  _pillWidth(
                    context,
                    working ? assistantStatus(t, session) : t.askPhin,
                  ),
                  min(AppTheme.assistantPillMaxWidth, area.width - 2 * margin),
                )
              : bubble;
          final windowWidth = min(
            area.width - 2 * margin,
            AppTheme.assistantWindowMaxWidth,
          );
          final windowHeight = max(
            0.0,
            min(area.height - 2 * margin, AppTheme.assistantWindowMaxHeight),
          );
          final tucked = !_open && !pill && !_shown;
          final width = _open ? windowWidth : bubbleWidth;
          final height = _open ? windowHeight : bubble;
          final colors = context.colors;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: AppTheme.assistantMorph,
                curve: Curves.easeOutCubic,
                right: !_open && (widget.makeRoom?.value ?? false)
                    ? -bubbleWidth - margin
                    : tucked
                    ? AppTheme.assistantPeek - bubble
                    : margin,
                bottom: _open ? margin : clearance + margin,
                width: width,
                height: height,
                child: AnimatedContainer(
                  duration: AppTheme.assistantMorph,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: colors.surfaceElevated,
                    borderRadius: BorderRadius.circular(
                      _open ? AppTheme.radiusLg : bubble / 2,
                    ),
                    border: Border.all(color: colors.surfaceBorderStrong),
                    boxShadow: AppTheme.popupShadow,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedSwitcher(
                    duration: AppTheme.assistantMorph,
                    switchInCurve: const Interval(
                      0.35,
                      1,
                      curve: Curves.easeOut,
                    ),
                    switchOutCurve: const Interval(
                      0.6,
                      1,
                      curve: Curves.easeIn,
                    ),
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    child: _open
                        ? _Reveal(
                            key: const ValueKey('assistantWindow'),
                            width: windowWidth,
                            height: windowHeight,
                            child: AssistantPanel(
                              session: session,
                              actions: widget.actions,
                              controls: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: t.newChat,
                                    onPressed: session.isEmpty
                                        ? null
                                        : _newChat,
                                    icon: const Icon(
                                      PhosphorIconsRegular.notePencil,
                                      size: AppTheme.icon18,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: t.minimize,
                                    onPressed: minimize,
                                    icon: const Icon(
                                      PhosphorIconsRegular.caretDown,
                                      size: AppTheme.icon18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _Reveal(
                            key: const ValueKey('assistantBubble'),
                            width: bubbleWidth,
                            height: bubble,
                            child: _Bubble(
                              session: session,
                              pill: pill,
                              label: working ? null : t.askPhin,
                              onTap: tucked ? _bring : open,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Lays [child] out at its final size and anchors it to the bottom right,
/// so while the frame around it grows or shrinks the content is uncovered
/// or covered rather than squeezed.
class _Reveal extends StatelessWidget {
  const _Reveal({
    super.key,
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OverflowBox(
      alignment: Alignment.bottomRight,
      minWidth: width,
      maxWidth: width,
      minHeight: height,
      maxHeight: height,
      child: child,
    );
  }
}

/// The minimised assistant: its orb alone, or as a pill with a line beside
/// it - what it is doing while it works, or [label] when given.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.session,
    required this.pill,
    required this.onTap,
    this.label,
  });

  final AssistantSession session;
  final bool pill;
  final VoidCallback onTap;
  final String? label;

  /// The pill's line, also what its width is measured with.
  static TextStyle textStyle(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(
        const TextStyle(fontSize: AppTheme.font13, fontWeight: FontWeight.w500),
      );

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    final text = label ?? assistantStatus(t, session);
    final working =
        session.mood == AssistantMood.working ||
        session.mood == AssistantMood.thinking;
    return Semantics(
      button: true,
      label: pill ? text : t.open,
      child: Tooltip(
        message: t.open,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppTheme.space6),
                child: AssistantOrb(
                  size: AppTheme.assistantBubble - 2 * AppTheme.space6,
                  mood: session.mood,
                  animate: pill || session.mood == AssistantMood.done,
                ),
              ),
              if (pill)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppTheme.space16),
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle(context).copyWith(
                        color: label != null || working
                            ? context.colors.textPrimary
                            : assistantMoodColor(context, session.mood),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
