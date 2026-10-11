import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';

/// The search bar over the top of a terminal pane. Only the controls - the
/// pane owns the matches, the highlights and the scrolling.
///
/// The field's `onEditingComplete` is a no-op so the keyboard stays up
/// across repeated enters.
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
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        border: Border(bottom: BorderSide(color: colors.surfaceDivider)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
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
                fontSize: 15,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: t.terminalSearch.hint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                prefixIcon: Icon(
                  PhosphorIconsFill.magnifyingGlass,
                  size: 18,
                  color: colors.textTertiary,
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
                      icon: Icon(
                        PhosphorIconsRegular.textAa,
                        size: 18,
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
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _BarButton(
            tooltip: t.terminalSearch.older,
            icon: PhosphorIconsRegular.arrowUp,
            onPressed: total == 0 ? null : onOlder,
          ),
          _BarButton(
            tooltip: t.terminalSearch.newer,
            icon: PhosphorIconsRegular.arrowDown,
            onPressed: total == 0 ? null : onNewer,
          ),
          _BarButton(
            tooltip: t.terminalSearch.close,
            icon: PhosphorIconsRegular.x,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, size: 18),
    color: context.colors.textSecondary,
    onPressed: onPressed,
  );
}
