import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/platform/desktop_window.dart';
import '../../theme/theme.dart';

/// Minimize, maximize and close, drawn by the app off a Mac - where the system
/// draws its own traffic lights - now that the system's title bar is gone.
///
/// The glyphs are painted, not icons: a 10pt square drawn in 1px lines is what
/// both Windows and the GTK themes draw, and no icon font has it at that
/// weight.
class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final window = DesktopWindow.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: window.maximized,
      builder: (context, maximized, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WindowButton(
            key: const ValueKey('windowMinimize'),
            tooltip: t.window.minimize,
            glyph: _Glyph.minimize,
            onPressed: window.minimize,
          ),
          _WindowButton(
            key: const ValueKey('windowMaximize'),
            tooltip: maximized ? t.window.restore : t.window.maximize,
            glyph: maximized ? _Glyph.restore : _Glyph.maximize,
            onPressed: window.toggleMaximize,
          ),
          _WindowButton(
            key: const ValueKey('windowClose'),
            tooltip: t.window.close,
            glyph: _Glyph.close,
            destructive: true,
            onPressed: window.close,
          ),
        ],
      ),
    );
  }
}

enum _Glyph { minimize, maximize, restore, close }

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    super.key,
    required this.tooltip,
    required this.glyph,
    required this.onPressed,
    this.destructive = false,
  });

  final String tooltip;
  final _Glyph glyph;
  final VoidCallback onPressed;

  /// Close turns red under the pointer, as it does everywhere these buttons
  /// come from.
  final bool destructive;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Color background;
    final Color foreground;
    if (widget.destructive && (_hovered || _pressed)) {
      background = _pressed ? colors.errorActive : colors.error;
      foreground = colors.textInverse;
    } else {
      background = _pressed
          ? colors.surfaceBorder
          : _hovered
          ? colors.surfaceCard
          : colors.surfaceCard.invisible;
      foreground = _hovered ? colors.textPrimary : colors.textSecondary;
    }
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onPressed();
          },
          child: ColoredBox(
            color: background,
            child: SizedBox(
              width: 46,
              height: double.infinity,
              child: CustomPaint(
                painter: _GlyphPainter(widget.glyph, foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..isAntiAlias = glyph == _Glyph.close;
    final c = size.center(Offset.zero);
    const s = 10.0;
    final box = Rect.fromCenter(center: c, width: s, height: s);
    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(
          Offset(box.left, c.dy + 0.5),
          Offset(box.right, c.dy + 0.5),
          paint,
        );
      case _Glyph.maximize:
        canvas.drawRect(box.deflate(0.5), paint);
      case _Glyph.restore:
        final front = Rect.fromLTWH(box.left, box.top + 2, s - 2, s - 2);
        canvas.drawRect(front.deflate(0.5), paint);
        final back = Path()
          ..moveTo(box.left + 2.5, box.top + 2)
          ..lineTo(box.left + 2.5, box.top + 0.5)
          ..lineTo(box.right - 0.5, box.top + 0.5)
          ..lineTo(box.right - 0.5, box.bottom - 2.5)
          ..lineTo(box.right - 2, box.bottom - 2.5);
        canvas.drawPath(back, paint);
      case _Glyph.close:
        canvas.drawLine(box.topLeft, box.bottomRight, paint);
        canvas.drawLine(box.topRight, box.bottomLeft, paint);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
