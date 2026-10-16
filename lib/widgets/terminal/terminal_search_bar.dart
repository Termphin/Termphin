import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../ui/bar_icon_button.dart';

/// The search bar above a terminal pane. Only the controls - the pane owns
/// the matches, the highlights and the scrolling.
///
/// One tight row, [kTerminalSearchBarHeight] tall: it takes its height out
/// of the terminal's, so every pixel of it is a line of output not shown.
///
/// The field's `onEditingComplete` is a no-op so the keyboard stays up
/// across repeated enters.
const double kTerminalSearchBarHeight = 36;

class TerminalSearchBar extends StatelessWidget {
  const TerminalSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.total,
    required this.current,
    required this.caseSensitive,
    required this.onChanged,
    required this.onToggleCase,
    required this.onOlder,
    required this.onNewer,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int total;

  /// Zero-based index of the match in focus; ignored when [total] is zero.
  final int current;
  final bool caseSensitive;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggleCase;
  final VoidCallback onOlder;
  final VoidCallback onNewer;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final hasQuery = controller.text.isNotEmpty;
    final count = !hasQuery
        ? ''
        : total == 0
        ? t.terminalSearch.noMatches
        : t.terminalSearch.matchCount(current: current + 1, total: total);

    return Container(
      height: kTerminalSearchBarHeight,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        border: Border(bottom: BorderSide(color: colors.surfaceDivider)),
      ),
      padding: const EdgeInsets.only(
        left: AppTheme.space10,
        right: AppTheme.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: (_) => onOlder(),
              onEditingComplete: () {},
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                fontFamily: AppTheme.uiFamily,
                fontSize: AppTheme.font14,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: t.terminalSearch.hint,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 26,
                  minHeight: kTerminalSearchBarHeight,
                ),
                suffixIconConstraints: const BoxConstraints(
                  minHeight: kTerminalSearchBarHeight,
                ),
                prefixIcon: Align(
                  widthFactor: 1,
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    PhosphorIconsFill.magnifyingGlass,
                    size: AppTheme.icon16,
                    color: colors.textTertiary,
                  ),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (count.isNotEmpty)
                      Text(
                        count,
                        style: colors.uiSmall.copyWith(
                          color: total == 0
                              ? colors.error
                              : colors.textTertiary,
                        ),
                      ),
                    IconButton(
                      tooltip: t.terminalSearch.matchCase,
                      isSelected: caseSensitive,
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggleCase,
                      constraints: const BoxConstraints.tightFor(
                        width: AppTheme.icon28,
                        height: AppTheme.icon28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        PhosphorIconsRegular.textAa,
                        size: AppTheme.icon16,
                        color: caseSensitive
                            ? colors.primary
                            : colors.textTertiary,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: caseSensitive
                            ? colors.primary.withValues(alpha: 0.15)
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppTheme.space4),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.space4),
          BarIconButton(
            tooltip: t.terminalSearch.older,
            icon: PhosphorIconsRegular.arrowUp,
            onPressed: total == 0 ? null : onOlder,
          ),
          BarIconButton(
            tooltip: t.terminalSearch.newer,
            icon: PhosphorIconsRegular.arrowDown,
            onPressed: total == 0 ? null : onNewer,
          ),
          BarIconButton(
            tooltip: t.terminalSearch.close,
            icon: PhosphorIconsRegular.x,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
