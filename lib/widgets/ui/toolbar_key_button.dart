import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/settings/toolbar_layout.dart';
import '../../theme/theme.dart';

/// One key of the special-keys toolbar.
///
/// Lives here rather than inside `special_keys_toolbar.dart` so the settings
/// editor can draw its slots with the very widget that draws them over a
/// session. The editor used to have its own tile, which meant the button
/// height, padding and scheme colours a user was choosing were never the ones
/// they were looking at.
class ToolbarKeyButton extends StatefulWidget {
  const ToolbarKeyButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.active = false,
    this.locked = false,
    this.repeatable = false,
    this.height = kToolbarButtonHeight,
    this.colorScheme = AppTheme.terminalSchemeDefault,
    this.onLongPress,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool active;
  final bool locked;

  /// Whether holding the key repeats it. Ignored when [onLongPress] is set -
  /// the editor binds long press to dragging instead.
  final bool repeatable;

  final double height;
  final TerminalColorScheme colorScheme;

  /// Set by the editor, where a long press means "pick this up", not "repeat".
  final VoidCallback? onLongPress;

  @override
  State<ToolbarKeyButton> createState() => _ToolbarKeyButtonState();
}

/// Labels like PAGE↑ or a custom text key have to survive a narrow screen
/// and a large system text scale without overflowing the button, so the
/// label is wrapped in a `FittedBox` that scales it down.
class _ToolbarKeyButtonState extends State<ToolbarKeyButton> {
  Timer? _repeatTimer;

  bool get _repeats => widget.repeatable && widget.onLongPress == null;

  void _startRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = Timer(const Duration(milliseconds: 200), () {
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        widget.onTap();
      });
    });
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.colorScheme;
    final baseColor = s.uiSurface.withValues(alpha: 0.45);
    final borderColor = s.uiBorder.withValues(alpha: 0.7);
    final activeColor = s.uiActiveBorder;

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      toggled: widget.active || widget.locked ? true : null,
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        onLongPressStart: _repeats ? (_) => _startRepeat() : null,
        onLongPressEnd: _repeats ? (_) => _stopRepeat() : null,
        onLongPressCancel: _repeats ? _stopRepeat : null,
        child: Material(
          color: widget.locked
              ? activeColor
              : widget.active
              ? activeColor.withValues(alpha: 0.7)
              : baseColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            highlightColor: activeColor.withValues(alpha: 0.24),
            splashColor: activeColor.withValues(alpha: 0.22),
            child: Container(
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(
                  color: widget.locked || widget.active
                      ? activeColor.withValues(alpha: 0.7)
                      : borderColor,
                ),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.active || widget.locked
                          ? s.foreground
                          : s.foreground.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An empty slot in the editor's grid: the same footprint as a key, drawn as
/// an outline so a gap reads as somewhere to drop rather than as damage.
class ToolbarEmptySlot extends StatelessWidget {
  const ToolbarEmptySlot({
    super.key,
    required this.height,
    required this.colorScheme,
    this.selected = false,
    this.highlighted = false,
    this.onTap,
    this.onLongPress,
  });

  final double height;
  final TerminalColorScheme colorScheme;

  /// The slot the next tapped key lands in.
  final bool selected;

  /// A drag is hovering over it.
  final bool highlighted;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = colorScheme.uiActiveBorder;
    final quiet = colorScheme.uiBorder.withValues(alpha: 0.45);
    final active = selected || highlighted;
    return GestureDetector(
      onLongPress: onLongPress,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: active ? accent : quiet,
              width: active ? 1.4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: active
              ? Icon(PhosphorIconsRegular.plus, size: 16, color: accent)
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
