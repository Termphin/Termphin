import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/completion/command_completion.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../ui/key_caps.dart';

/// Most suggestions shown at once.
const kMaxShownSuggestions = 3;

/// Height one row is assumed to take when deciding how many fit: two lines,
/// the most a long command wraps to.
const _kRowHeight = 54.0;

/// Height the line naming the keys takes under the rows, divider included.
const _kKeyHintHeight = 34.0;

/// Kept clear between the popup and the screen's edges and the cursor row.
const _kMargin = 8.0;
const _kGap = 4.0;

/// How far left of the cursor the card starts, so its icons sit before the
/// text rather than over it.
const _kLeadIn = 28.0;

/// The likeliest next commands, stacked over the line being typed.
///
/// Over the terminal rather than beside it, so it never takes a row away from
/// the pane - which would resize the remote pty on every keystroke. The best
/// one sits next to the cursor: at the bottom of the stack above the line, at
/// the top of it below.
class CommandSuggestionPopup extends StatelessWidget {
  const CommandSuggestionPopup({
    super.key,
    required this.cursor,
    required this.suggestions,
    required this.onAccept,
    required this.onDismiss,
    this.keyboard = false,
    this.selected = 0,
  });

  /// Whether the popup opens above the line for a cursor at [cursor] - where
  /// the best suggestion is the bottom row rather than the top one.
  static bool opensAbove(Rect cursor) =>
      cursor.top - _kGap - _kMargin >= _kRowHeight;

  /// Worked from the keyboard, as on a desktop: the picked row is drawn as
  /// such, and a line under the rows says which keys do what. That line only
  /// shows where there is room for it beside a row; a cursor hard against an
  /// edge gets the rows alone.
  final bool keyboard;

  /// The suggestion the keyboard is on, best first.
  final int selected;

  /// The cursor's cell, in the enclosing Stack.
  final Rect cursor;

  /// Best first.
  final List<CommandSuggestion> suggestions;

  final ValueChanged<CommandSuggestion> onAccept;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final roomAbove = cursor.top - _kGap - _kMargin;
          final roomBelow =
              constraints.maxHeight - cursor.bottom - _kGap - _kMargin;
          final above = opensAbove(cursor);
          final room = above ? roomAbove : roomBelow;
          final hint = keyboard && room >= _kRowHeight + _kKeyHintHeight;
          final fit = ((room - (hint ? _kKeyHintHeight : 0)) / _kRowHeight)
              .floor();
          final count = math.min(
            math.min(suggestions.length, kMaxShownSuggestions),
            math.max(fit, 1),
          );
          final shown = suggestions.take(count).toList();
          final pick = selected.clamp(0, count - 1);
          return CustomSingleChildLayout(
            delegate: _PopupLayout(cursor, above: above),
            child: _Card(
              suggestions: above ? shown.reversed.toList() : shown,
              selected: keyboard ? (above ? count - 1 - pick : pick) : null,
              keyHint: hint,
              onAccept: onAccept,
              onDismiss: onDismiss,
            ),
          );
        },
      ),
    );
  }
}

/// Puts the card over the cursor, measured first: it starts at the cursor
/// and only moves left as far as it has to to stay on screen.
class _PopupLayout extends SingleChildLayoutDelegate {
  const _PopupLayout(this.cursor, {required this.above});

  final Rect cursor;

  final bool above;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(0, constraints.maxWidth - 2 * _kMargin),
        maxHeight: math.max(
          0,
          above
              ? cursor.top - _kGap - _kMargin
              : constraints.maxHeight - cursor.bottom - _kGap - _kMargin,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final maxLeft = math.max(_kMargin, size.width - child.width - _kMargin);
    final left = (cursor.left - _kLeadIn).clamp(_kMargin, maxLeft);
    final top = above
        ? cursor.top - _kGap - child.height
        : cursor.bottom + _kGap;
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_PopupLayout old) =>
      old.cursor != cursor || old.above != above;
}

class _Card extends StatelessWidget {
  const _Card({
    required this.suggestions,
    required this.selected,
    required this.keyHint,
    required this.onAccept,
    required this.onDismiss,
  });

  /// In the order drawn, top to bottom.
  final List<CommandSuggestion> suggestions;

  /// The picked row, in the order drawn; null when nothing is drawn picked.
  final int? selected;

  /// Whether to name the keys under the rows. The line is scaled down rather
  /// than wrapped, which the room set aside for it would not hold, and the
  /// rows - and the X after them - run to the card's edge when it is the
  /// wider of the two.
  final bool keyHint;

  final ValueChanged<CommandSuggestion> onAccept;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;

    return Material(
      color: colors.surfaceCard,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(color: colors.surfaceBorderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < suggestions.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, color: colors.surfaceDivider),
                            _Row(
                              suggestion: suggestions[i],
                              picked: i == selected,
                              onTap: () => onAccept(suggestions[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, color: colors.surfaceDivider),
                  Semantics(
                    button: true,
                    label: t.terminal.suggestionDismiss,
                    child: InkWell(
                      key: const ValueKey('commandSuggestionDismiss'),
                      onTap: onDismiss,
                      child: SizedBox(
                        width: 40,
                        child: Icon(
                          PhosphorIconsRegular.x,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (keyHint) ...[
              Divider(height: 1, color: colors.surfaceDivider),
              Container(
                color: colors.fieldFill,
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SuggestionKeys(key: ValueKey('commandSuggestionKeys')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The keys that work the suggestions on a desktop, each drawn as a key and
/// named for what it does - under the popup's rows, and in Settings beside
/// the switch. Ctrl off a Mac, Cmd on one: see
/// `SessionViewState._onSuggestionKey`.
class SuggestionKeys extends StatelessWidget {
  const SuggestionKeys({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final modifier = isMacOSPlatform ? '⌘' : 'Ctrl';
    final label = colors.uiSmall.copyWith(
      fontSize: 11.5,
      color: colors.textTertiary,
    );
    Widget pair(List<String> keys, String does) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyCaps(keys),
        const SizedBox(width: 5),
        Text(does, style: label),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pair([modifier, '↑↓'], t.terminal.suggestionPick),
        const SizedBox(width: 12),
        pair([modifier, '→'], t.terminal.suggestionInsert),
        const SizedBox(width: 12),
        pair(const ['Esc'], t.terminal.suggestionClose),
      ],
    );
  }
}

/// What is already on the line is shown dimmed, so the eye goes to what a
/// tap would add.
class _Row extends StatelessWidget {
  const _Row({
    required this.suggestion,
    required this.picked,
    required this.onTap,
  });

  final CommandSuggestion suggestion;

  final bool picked;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = TextStyle(
      fontFamily: AppTheme.monoFamily,
      fontSize: 13,
      height: 1.3,
      color: colors.textPrimary,
    );
    final label = suggestion.label;
    final typed =
        suggestion.kind == SuggestionKind.history && suggestion.insert != label
        ? label.substring(0, label.length - suggestion.insert.length)
        : '';

    return InkWell(
      key: ValueKey('commandSuggestion-$label'),
      onTap: onTap,
      child: Container(
        color: picked
            ? colors.primaryHighlight
            : colors.primaryHighlight.invisible,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            Icon(
              suggestion.kind == SuggestionKind.history
                  ? PhosphorIconsRegular.clockCounterClockwise
                  : PhosphorIconsRegular.lightning,
              size: 14,
              color: colors.textTertiary,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (typed.isNotEmpty)
                      TextSpan(
                        text: typed,
                        style: TextStyle(color: colors.textTertiary),
                      ),
                    TextSpan(text: typed.isEmpty ? label : suggestion.insert),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
