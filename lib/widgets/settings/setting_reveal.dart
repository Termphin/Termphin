import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';

/// Brings the setting titled [focus] into view once its screen has built,
/// and washes its row in the accent for a moment so the eye lands on it:
/// what a search result does after opening the screen the setting is on.
///
/// The screen's sections load on their own, some of them from the platform,
/// so the title is looked for again over the first [patience] after the
/// screen has finished sliding in, until it is there. The row is the nearest list tile around the title.
class SettingReveal extends StatefulWidget {
  const SettingReveal({super.key, required this.focus, required this.child});

  final String? focus;
  final Widget child;

  static const patience = Duration(milliseconds: 1500);
  static const _retry = Duration(milliseconds: 100);
  static const _glow = Duration(milliseconds: 1400);

  @override
  State<SettingReveal> createState() => _SettingRevealState();
}

class _SettingRevealState extends State<SettingReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: SettingReveal._glow,
  );
  Timer? _retry;
  OverlayEntry? _entry;
  DateTime? _started;

  @override
  void initState() {
    super.initState();
    if (widget.focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _afterEntrance());
    }
  }

  /// While the screen is still sliding in, its scroll view is not laid out
  /// at its full length and has nowhere to scroll to; the search starts
  /// once it has landed.
  void _afterEntrance() {
    if (!mounted) return;
    final entrance = ModalRoute.of(context)?.animation;
    if (entrance == null || entrance.isCompleted) {
      _start();
      return;
    }
    void landed(AnimationStatus status) {
      if (!status.isCompleted) return;
      entrance.removeStatusListener(landed);
      _start();
    }

    entrance.addStatusListener(landed);
  }

  void _start() {
    _started = DateTime.now();
    _look();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _entry?.remove();
    _glow.dispose();
    super.dispose();
  }

  void _look() {
    if (!mounted) return;
    final row = _findRow(context, widget.focus!);
    if (row != null) {
      unawaited(_reveal(row));
      return;
    }
    if (DateTime.now().difference(_started!) > SettingReveal.patience) return;
    _retry = Timer(SettingReveal._retry, _look);
  }

  Future<void> _reveal(Element row) async {
    await Scrollable.ensureVisible(
      row,
      alignment: 0.3,
      duration: AppTheme.motionSlow,
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !row.mounted) return;
    final box = row.renderObject;
    final overlay = Overlay.maybeOf(context);
    if (box is! RenderBox || !box.attached || overlay == null) return;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final rect =
        box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
    final color = context.colors.primary;
    _entry = OverlayEntry(
      builder: (_) => Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _glow,
            builder: (_, _) => DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(
                  alpha: 0.18 * (1 - Curves.easeIn.transform(_glow.value)),
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    await _glow.forward();
    _entry?.remove();
    _entry = null;
  }

  /// The list tile holding a text that reads [title], or the text itself
  /// when it sits in no tile.
  static Element? _findRow(BuildContext context, String title) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      final text = switch (widget) {
        Text(:final data?) => data,
        Text(:final textSpan?) => textSpan.toPlainText(),
        _ => null,
      };
      if (text == title) {
        found = element;
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    final text = found;
    if (text == null) return null;
    Element? tile;
    text.visitAncestorElements((ancestor) {
      if (ancestor.widget is ListTile) {
        tile = ancestor;
        return false;
      }
      return true;
    });
    return tile ?? text;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
