import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:re_editor/re_editor.dart' as re;

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';

/// Find, and in an editable file replace, above the text.
///
/// re_editor does the searching - on its own isolate, over the lines it holds
/// - and draws the matches; this is only the bar that drives it. Built for a
/// phone: the two options sit inside the search field instead of taking a row
/// of their own, and replace is a second row that only appears when asked for.
class EditorFindBar extends StatelessWidget implements PreferredSizeWidget {
  const EditorFindBar({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  final re.CodeFindController controller;
  final bool readOnly;

  static const double _rowHeight = 52;

  @override
  Size get preferredSize {
    final value = controller.value;
    if (value == null) return Size.zero;
    final rows = value.replaceMode && !readOnly ? 2 : 1;
    return Size.fromHeight(_rowHeight * rows + 8);
  }

  /// Esc closes the bar from either field, before it can reach the editor
  /// window behind it and close that instead.
  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();
    final t = Translations.of(context);
    final colors = context.colors;
    final result = value.result;
    final total = result?.matches.length ?? 0;
    final replacing = value.replaceMode && !readOnly;
    final hasPattern = value.option.pattern.isNotEmpty;

    final count = !hasPattern
        ? ''
        : total == 0
        ? t.editor.noMatches
        : t.editor.matchCount(current: result!.index + 1, total: total);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): controller.close,
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          border: Border(bottom: BorderSide(color: colors.surfaceDivider)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _rowHeight,
              child: Row(
                children: [
                  if (!readOnly)
                    _BarButton(
                      tooltip: t.editor.replace,
                      icon: replacing
                          ? PhosphorIconsRegular.caretDown
                          : PhosphorIconsRegular.caretRight,
                      onPressed: controller.toggleMode,
                    ),
                  Expanded(
                    child: _Field(
                      controller: controller.findInputController,
                      focusNode: controller.findInputFocusNode,
                      hint: t.editor.findHint,
                      onSubmitted: (_) => controller.nextMatch(),
                      trailing: [
                        _OptionToggle(
                          label: 'Aa',
                          tooltip: t.editor.matchCase,
                          on: value.option.caseSensitive,
                          onTap: controller.toggleCaseSensitive,
                        ),
                        _OptionToggle(
                          label: '.*',
                          tooltip: t.editor.regex,
                          on: value.option.regex,
                          onTap: controller.toggleRegex,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      count,
                      style: colors.uiSmall.copyWith(
                        color: total == 0 && hasPattern
                            ? colors.error
                            : colors.textTertiary,
                      ),
                    ),
                  ),
                  _BarButton(
                    tooltip: t.editor.previousMatch,
                    icon: PhosphorIconsRegular.arrowUp,
                    onPressed: total == 0 ? null : controller.previousMatch,
                  ),
                  _BarButton(
                    tooltip: t.editor.nextMatch,
                    icon: PhosphorIconsRegular.arrowDown,
                    onPressed: total == 0 ? null : controller.nextMatch,
                  ),
                  _BarButton(
                    tooltip: t.editor.closeFind,
                    icon: PhosphorIconsRegular.x,
                    onPressed: controller.close,
                  ),
                ],
              ),
            ),
            if (replacing)
              SizedBox(
                height: _rowHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: _Field(
                        controller: controller.replaceInputController,
                        focusNode: controller.replaceInputFocusNode,
                        hint: t.editor.replaceHint,
                        onSubmitted: (_) => controller.replaceMatch(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: total == 0 ? null : controller.replaceMatch,
                      child: Text(t.editor.replace),
                    ),
                    TextButton(
                      onPressed: total == 0
                          ? null
                          : controller.replaceAllMatches,
                      child: Text(t.editor.replaceAll),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmitted,
    this.trailing = const [],
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.fieldFill,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onSubmitted: onSubmitted,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.search,
              style: colors.monoStyle.copyWith(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

class _OptionToggle extends StatelessWidget {
  const _OptionToggle({
    required this.label,
    required this.tooltip,
    required this.on,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: on ? colors.primary.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusXs),
          ),
          child: Text(
            label,
            style: colors.monoSmall.copyWith(
              color: on ? colors.primary : colors.textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
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
