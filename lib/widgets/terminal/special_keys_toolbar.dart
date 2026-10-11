import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings/toolbar_layout.dart';
import '../../theme/theme.dart';
import '../ui/toolbar_key_button.dart';

export '../../services/settings/toolbar_layout.dart';

enum CtrlMode { off, oneshot, locked }

enum ShiftMode { off, oneshot, locked }

enum AltMode { off, oneshot, locked }

/// Screen-reader label for [action], derived from the same table the button
/// renders from.
String toolbarActionSemanticLabel(Translations t, ToolbarAction action) {
  final id = action.id;
  switch (id) {
    case 'esc':
      return t.toolbar.escape;
    case 'tab':
      return t.toolbar.tab;
    case 's_tab':
      return t.toolbar.backTab;
    case 'home':
      return t.toolbar.home;
    case 'end':
      return t.toolbar.end;
    case 'ctrl':
      return t.toolbar.control;
    case 'alt':
      return t.toolbar.alt;
    case 'shift':
      return t.toolbar.shift;
    case 'cr':
      return t.toolbar.enter;
    case 'del':
      return t.toolbar.delete;
    case 'backspace':
      return t.toolbar.backspace;
    case 'page_up':
      return t.toolbar.pageUp;
    case 'page_down':
      return t.toolbar.pageDown;
    case 'insert':
      return t.toolbar.insert;
    case 'space':
      return t.toolbar.space;
    case 'arrow_left':
      return t.toolbar.arrowLeft;
    case 'arrow_up':
      return t.toolbar.arrowUp;
    case 'arrow_down':
      return t.toolbar.arrowDown;
    case 'arrow_right':
      return t.toolbar.arrowRight;
    case 'hide_keyboard':
      return t.toolbar.hideKeyboard;
  }
  if (id.startsWith('f') && int.tryParse(id.substring(1)) != null) {
    return t.toolbar.functionKey(number: id.substring(1));
  }
  if (id.startsWith('ctrl_')) {
    return t.toolbar.ctrlCombo(key: id.substring(5).toUpperCase());
  }
  switch (action.kind) {
    case ToolbarActionKind.text:
      return t.toolbar.sendText(text: action.payload ?? action.label);
    case ToolbarActionKind.snippet:
      return t.toolbar.runSnippet;
    case ToolbarActionKind.dismissKeyboard:
      return t.toolbar.hideKeyboard;
    default:
      return t.toolbar.symbol(char: action.label);
  }
}

class SpecialKeysToolbar extends StatefulWidget {
  const SpecialKeysToolbar({
    super.key,
    required this.onKey,
    required this.ctrlNotifier,
    required this.altNotifier,
    this.shiftNotifier,
    this.onDismissKeyboard,
    this.backgroundColor,
    this.borderColor,
    this.colorScheme,
    this.onRunSnippet,
    this.snippetLabels = const {},
  });

  final void Function(Uint8List data) onKey;
  final ValueNotifier<CtrlMode> ctrlNotifier;
  final ValueNotifier<AltMode> altNotifier;
  final VoidCallback? onDismissKeyboard;

  /// Shared with the session so shift also applies to what the soft keyboard
  /// types, not just to the toolbar's own keys. A private one is used when
  /// omitted.
  final ValueNotifier<ShiftMode>? shiftNotifier;

  /// Null falls back to the palette in force where the toolbar is built.
  final Color? backgroundColor;
  final Color? borderColor;
  final TerminalColorScheme? colorScheme;

  /// Invoked with a snippet id when a snippet-bound slot is tapped.
  final void Function(String snippetId)? onRunSnippet;

  /// Snippet id → name, for labelling snippet slots.
  final Map<String, String> snippetLabels;

  @override
  State<SpecialKeysToolbar> createState() => _SpecialKeysToolbarState();
}

class _SpecialKeysToolbarState extends State<SpecialKeysToolbar> {
  static const _kRowGap = 3.0;
  static const _kIndicatorGap = 4.0;

  /// 2px line plus the padding that turns it into a real touch target.
  static const _kIndicatorHeight = 10.0;

  final _fallbackShiftNotifier = ValueNotifier<ShiftMode>(ShiftMode.off);
  final _activePageNotifier = ValueNotifier<int>(0);
  late final PageController _pageController;

  ValueNotifier<ShiftMode> get _shiftNotifier =>
      widget.shiftNotifier ?? _fallbackShiftNotifier;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _activePageNotifier.dispose();
    _fallbackShiftNotifier.dispose();
    super.dispose();
  }

  void _send(List<int> bytes) {
    HapticFeedback.lightImpact();
    widget.onKey(Uint8List.fromList(bytes));
  }

  void _consumeShiftOneshot() {
    if (_shiftNotifier.value == ShiftMode.oneshot) {
      _shiftNotifier.value = ShiftMode.off;
    }
  }

  void _toggleShift() {
    HapticFeedback.lightImpact();
    _shiftNotifier.value = switch (_shiftNotifier.value) {
      ShiftMode.off => ShiftMode.oneshot,
      ShiftMode.oneshot => ShiftMode.locked,
      ShiftMode.locked => ShiftMode.off,
    };
  }

  void _toggleCtrl() {
    HapticFeedback.lightImpact();
    widget.ctrlNotifier.value = switch (widget.ctrlNotifier.value) {
      CtrlMode.off => CtrlMode.oneshot,
      CtrlMode.oneshot => CtrlMode.locked,
      CtrlMode.locked => CtrlMode.off,
    };
  }

  void _toggleAlt() {
    HapticFeedback.lightImpact();
    widget.altNotifier.value = switch (widget.altNotifier.value) {
      AltMode.off => AltMode.oneshot,
      AltMode.oneshot => AltMode.locked,
      AltMode.locked => AltMode.off,
    };
  }

  void _sendArrow(int arrowCode) {
    final shifted = _shiftNotifier.value != ShiftMode.off;
    _send(
      shifted
          ? [0x1b, 0x5b, 0x31, 0x3b, 0x32, arrowCode]
          : [0x1b, 0x5b, arrowCode],
    );
    _consumeShiftOneshot();
  }

  void _runAction(ToolbarAction action) {
    switch (action.kind) {
      case ToolbarActionKind.modifier:
        switch (action.id) {
          case 'ctrl':
            _toggleCtrl();
          case 'alt':
            _toggleAlt();
          case 'shift':
            _toggleShift();
        }
      case ToolbarActionKind.arrow:
        _sendArrow(action.arrowCode);
      case ToolbarActionKind.bytes:
        final shiftBytes = action.shiftBytes;
        if (shiftBytes != null && _shiftNotifier.value != ShiftMode.off) {
          _send(shiftBytes);
          _consumeShiftOneshot();
        } else {
          _send(action.bytes);
        }
      case ToolbarActionKind.text:
        _send(action.bytes);
      case ToolbarActionKind.snippet:
        final snippetId = action.payload;
        if (snippetId == null) return;
        HapticFeedback.lightImpact();
        widget.onRunSnippet?.call(snippetId);
      case ToolbarActionKind.dismissKeyboard:
        HapticFeedback.lightImpact();
        widget.onDismissKeyboard?.call();
    }
  }

  TerminalColorScheme get _scheme =>
      widget.colorScheme ?? toolbarSchemeFromTheme(context);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ToolbarLayout>(
      valueListenable: toolbarSettings.layout,
      builder: (context, layout, _) => _buildToolbar(context, layout),
    );
  }

  Widget _buildToolbar(BuildContext context, ToolbarLayout layout) {
    final scheme = _scheme;
    final visiblePages = layout.visiblePages;
    final showIndicator = visiblePages.length > 1;

    if (_activePageNotifier.value >= visiblePages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(0);
        _activePageNotifier.value = 0;
      });
    }

    final gridHeight =
        layout.rows * layout.buttonHeight + (layout.rows - 1) * _kRowGap;

    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? context.colors.backgroundPrimary,
        border: Border(
          top: BorderSide(
            color: (widget.borderColor ?? context.colors.surfaceBorder)
                .withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.only(left: 4, right: 4, top: 6, bottom: 3),
      child: SizedBox(
        height:
            gridHeight +
            (showIndicator ? _kIndicatorGap + _kIndicatorHeight : 0),
        child: Column(
          children: [
            Expanded(
              child: ClipRect(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const PageScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  itemCount: visiblePages.length,
                  onPageChanged: (index) => _activePageNotifier.value = index,
                  itemBuilder: (context, index) =>
                      _buildLayoutPage(layout, visiblePages[index]),
                ),
              ),
            ),
            if (showIndicator) ...[
              const SizedBox(height: _kIndicatorGap),
              _buildPageIndicator(visiblePages.length, scheme),
            ],
          ],
        ),
      ),
    );
  }

  /// Each dash's padding gives it a real touch target without changing how
  /// it looks - a 2px line on its own would be untappable.
  Widget _buildPageIndicator(int pageCount, TerminalColorScheme scheme) {
    final t = Translations.of(context);
    final indicatorActive = scheme.blue;
    final indicatorInactive = scheme.uiBorder.withValues(alpha: 0.65);

    return ValueListenableBuilder<int>(
      valueListenable: _activePageNotifier,
      builder: (context, active, _) {
        return Row(
          children: [
            for (int i = 0; i < pageCount; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == active,
                  label: t.toolbar.goToPage(number: '${i + 1}'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _pageController.animateToPage(
                        i,
                        duration: AppTheme.motionFast,
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: AnimatedContainer(
                        duration: AppTheme.motionFast,
                        height: 2,
                        decoration: BoxDecoration(
                          color: i == active
                              ? indicatorActive
                              : indicatorInactive,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// A row nobody put a key on is dropped entirely rather than left as a
  /// band of dead space.
  Widget _buildLayoutPage(ToolbarLayout layout, int page) {
    final ids = layout.pageIds(page);
    final rows = <Widget>[];
    for (int row = 0; row < layout.rows; row++) {
      final rowIds = ids
          .skip(row * layout.columns)
          .take(layout.columns)
          .toList();
      if (rowIds.every((id) => id.isEmpty)) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: _kRowGap));
      rows.add(_buildRow(rowIds, layout.buttonHeight));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: rows,
    );
  }

  Widget _buildRow(List<String> ids, double buttonHeight) {
    return Row(
      children: [
        for (final id in ids)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildAction(id, buttonHeight),
            ),
          ),
      ],
    );
  }

  Widget _buildAction(String id, double buttonHeight) {
    final action = toolbarActionForId(id);
    if (action == null) return SizedBox(height: buttonHeight);
    final scheme = _scheme;
    final t = Translations.of(context);
    final semanticLabel = toolbarActionSemanticLabel(t, action);

    Widget button({
      String? label,
      bool active = false,
      bool locked = false,
      VoidCallback? onTap,
    }) {
      return ToolbarKeyButton(
        label: label ?? action.label,
        semanticLabel: semanticLabel,
        onTap: onTap ?? () => _runAction(action),
        active: active,
        locked: locked,
        repeatable: action.repeatable,
        height: buttonHeight,
        colorScheme: scheme,
      );
    }

    switch (action.id) {
      case 'ctrl':
        return ValueListenableBuilder<CtrlMode>(
          valueListenable: widget.ctrlNotifier,
          builder: (context, mode, _) => button(
            label: mode == CtrlMode.locked ? 'CTRL⇩' : 'CTRL',
            active: mode != CtrlMode.off,
            locked: mode == CtrlMode.locked,
          ),
        );
      case 'alt':
        return ValueListenableBuilder<AltMode>(
          valueListenable: widget.altNotifier,
          builder: (context, mode, _) => button(
            label: mode == AltMode.locked ? 'ALT⇩' : 'ALT',
            active: mode != AltMode.off,
            locked: mode == AltMode.locked,
          ),
        );
      case 'shift':
        return ValueListenableBuilder<ShiftMode>(
          valueListenable: _shiftNotifier,
          builder: (context, mode, _) => button(
            label: mode == ShiftMode.locked ? 'SHIFT⇩' : 'SHIFT',
            active: mode != ShiftMode.off,
            locked: mode == ShiftMode.locked,
          ),
        );
    }

    if (action.kind == ToolbarActionKind.snippet) {
      final name = widget.snippetLabels[action.payload];
      return button(label: shortToolbarLabel(name ?? action.label));
    }

    return button(label: shortToolbarLabel(action.label));
  }
}

/// The toolbar's palette when no terminal scheme is in force, derived from
/// the app theme.
///
/// Shared with the settings editor so its slots are drawn in the colours
/// the toolbar itself uses, rather than in a second palette that could
/// drift from this one.
TerminalColorScheme toolbarSchemeFromTheme(BuildContext context) {
  final theme = Theme.of(context);
  final onSurface = theme.colorScheme.onSurface;
  final surface = theme.colorScheme.surface;
  final bg = theme.scaffoldBackgroundColor;
  final primary = theme.colorScheme.primary;
  final error = theme.colorScheme.error;
  return TerminalColorScheme(
    background: bg,
    foreground: onSurface,
    cursor: primary,
    selection: primary.withValues(alpha: 0.28),
    black: const Color(0xFF111111),
    red: error,
    green: context.colors.success,
    yellow: context.colors.warning,
    blue: primary,
    magenta: const Color(0xFF8B5CF6),
    cyan: const Color(0xFF06B6D4),
    white: onSurface.withValues(alpha: 0.9),
    brightBlack: const Color(0xFF6B7280),
    brightRed: error,
    brightGreen: context.colors.success,
    brightYellow: context.colors.warning,
    brightBlue: primary,
    brightMagenta: const Color(0xFFA78BFA),
    brightCyan: const Color(0xFF22D3EE),
    brightWhite: onSurface,
    uiBorder: theme.dividerColor,
    uiSurface: surface,
    uiActiveBorder: primary.withValues(alpha: 0.35),
  );
}
