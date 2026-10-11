import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/completion/command_completion.dart';
import '../../theme/theme.dart';

/// Most suggestions shown at once.
const kMaxShownSuggestions = 3;

/// Height one row is assumed to take when deciding how many fit: two lines,
/// the most a long command wraps to.
const _kRowHeight = 54.0;

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
  });

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
          final above = roomAbove >= _kRowHeight;
          final fit = ((above ? roomAbove : roomBelow) / _kRowHeight).floor();
          final count = math.min(
            math.min(suggestions.length, kMaxShownSuggestions),
            math.max(fit, 1),
          );
          final shown = suggestions.take(count).toList();
          return CustomSingleChildLayout(
            delegate: _PopupLayout(cursor, above: above),
            child: _Card(
              suggestions: above ? shown.reversed.toList() : shown,
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
    required this.onAccept,
    required this.onDismiss,
  });

  /// In the order drawn, top to bottom.
  final List<CommandSuggestion> suggestions;

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
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
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
    );
  }
}

/// What is already on the line is shown dimmed, so the eye goes to what a
/// tap would add.
class _Row extends StatelessWidget {
  const _Row({required this.suggestion, required this.onTap});

  final CommandSuggestion suggestion;

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
      child: Padding(
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
