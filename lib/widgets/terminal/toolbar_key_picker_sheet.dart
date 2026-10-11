import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings/toolbar_layout.dart';
import '../../theme/theme.dart';
import '../ui/toolbar_key_button.dart';
import 'special_keys_toolbar.dart' show toolbarSchemeFromTheme;

String toolbarCategoryLabel(Translations t, ToolbarActionCategory category) {
  return switch (category) {
    ToolbarActionCategory.navigation => t.toolbar.categoryNavigation,
    ToolbarActionCategory.editing => t.toolbar.categoryEditing,
    ToolbarActionCategory.modifiers => t.toolbar.categoryModifiers,
    ToolbarActionCategory.function => t.toolbar.categoryFunction,
    ToolbarActionCategory.symbols => t.toolbar.categorySymbols,
    ToolbarActionCategory.custom => t.toolbar.categoryCustom,
  };
}

/// Lets the user pick a key for a toolbar slot: one of their custom keys, one
/// of their snippets, or any unused built-in. Returns the slot id, or null when
/// dismissed.
Future<String?> showCustomKeyEditor(
  BuildContext context, {
  ToolbarAction? initial,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => _CustomKeyBuilderScreen(initial: initial),
      fullscreenDialog: true,
    ),
  );
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: ToolbarKeyButton(
        label: label,
        semanticLabel: label,
        onTap: onTap,
        active: selected,
        height: 36,
        colorScheme: toolbarSchemeFromTheme(context),
      ),
    );
  }
}

/// Builds a custom key by tapping it out: hold the modifiers you want, then hit
/// the key. No naming step - the label is the combo itself (`Ctrl+R`, `Alt+Shift+←`).
///
/// The second tab covers the other kind of custom key, a literal piece of text.
class _CustomKeyBuilderScreen extends StatefulWidget {
  const _CustomKeyBuilderScreen({this.initial});

  final ToolbarAction? initial;

  @override
  State<_CustomKeyBuilderScreen> createState() =>
      _CustomKeyBuilderScreenState();
}

class _CustomKeyBuilderScreenState extends State<_CustomKeyBuilderScreen> {
  /// The capture field keeps a zero-width space in it: deleting that is how a
  /// backspace press shows up as a change instead of doing nothing.
  static const _sentinel = '\u200b';

  final _keyboardFocus = FocusNode();
  final _captureController = TextEditingController(text: _sentinel);
  final _captureFocus = FocusNode();
  late final TextEditingController _textController;
  late bool _appendEnter;
  late bool _textMode;
  String? _capturedKey;
  bool _ctrl = false;
  bool _alt = false;
  bool _shift = false;

  /// The capture box highlights while it holds focus, so its listener
  /// triggers a rebuild on every focus change.
  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _textController = TextEditingController(text: initial?.payload ?? '');
    _appendEnter = initial?.appendEnter ?? false;
    _textMode = initial != null && initial.kind == ToolbarActionKind.text;
    _captureFocus.addListener(() {
      if (mounted) setState(() {});
    });

    final combo = initial == null ? null : parseToolbarComboId(initial.id);
    if (combo != null) {
      _ctrl = combo.ctrl;
      _alt = combo.alt;
      _shift = combo.shift;
      _capturedKey = combo.key;
    }
  }

  @override
  void dispose() {
    _keyboardFocus.dispose();
    _captureFocus.dispose();
    _captureController.dispose();
    _textController.dispose();
    super.dispose();
  }

  ToolbarCombo? get _combo {
    final key = _capturedKey;
    if (key == null) return null;
    return ToolbarCombo(key: key, ctrl: _ctrl, alt: _alt, shift: _shift);
  }

  void _capture(String key, {bool shift = false}) {
    HapticFeedback.selectionClick();
    setState(() {
      _capturedKey = key;
      if (shift) _shift = true;
    });
  }

  /// Whatever the soft keyboard typed becomes the key. An empty result
  /// means everything was deleted, which means the user pressed backspace.
  void _onCaptureChanged(String value) {
    final typed = value.replaceAll(_sentinel, '');
    _resetCaptureField();
    if (typed.isEmpty) {
      _capture('backspace');
      return;
    }
    final combo = comboFromTypedCharacter(typed.characters.last);
    _capture(combo.key, shift: combo.shift);
  }

  /// Puts the soft keyboard back up when the capture box is tapped.
  ///
  /// `requestFocus` on a node that already has focus is a no-op, and the field
  /// keeps its focus when Android hides the keyboard on its own - the back
  /// button, or a tap on a modifier chip. That left the box looking focused,
  /// with no keyboard and no way to ask for one back.
  void _focusCapture() {
    if (_captureFocus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      return;
    }
    _captureFocus.requestFocus();
  }

  void _resetCaptureField() {
    _captureController.value = const TextEditingValue(
      text: _sentinel,
      selection: TextSelection.collapsed(offset: _sentinel.length),
    );
  }

  void _submitCombo() {
    final combo = _combo;
    if (combo == null) return;
    Navigator.pop(context, toolbarComboActionId(combo));
  }

  /// A physical keyboard, when there is one, fills the same field.
  void _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = _hardwareKeyToken(event.logicalKey);
    if (key == null) return;
    final pressed = HardwareKeyboard.instance;
    setState(() {
      _ctrl = _ctrl || pressed.isControlPressed;
      _alt = _alt || pressed.isAltPressed;
      _shift = _shift || pressed.isShiftPressed;
    });
    _capture(key);
  }

  static String? _hardwareKeyToken(LogicalKeyboardKey logicalKey) {
    final named = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.tab: 'tab',
      LogicalKeyboardKey.enter: 'cr',
      LogicalKeyboardKey.escape: 'esc',
      LogicalKeyboardKey.space: 'space',
      LogicalKeyboardKey.backspace: 'backspace',
      LogicalKeyboardKey.delete: 'del',
      LogicalKeyboardKey.insert: 'insert',
      LogicalKeyboardKey.home: 'home',
      LogicalKeyboardKey.end: 'end',
      LogicalKeyboardKey.pageUp: 'page_up',
      LogicalKeyboardKey.pageDown: 'page_down',
      LogicalKeyboardKey.arrowLeft: 'arrow_left',
      LogicalKeyboardKey.arrowRight: 'arrow_right',
      LogicalKeyboardKey.arrowUp: 'arrow_up',
      LogicalKeyboardKey.arrowDown: 'arrow_down',
    };
    final mapped = named[logicalKey];
    if (mapped != null) return mapped;

    final label = logicalKey.keyLabel.toLowerCase();
    if (label.length == 1 &&
        (kComboLetterKeys.contains(label) || kComboDigitKeys.contains(label))) {
      return label;
    }
    if (kComboFunctionKeys.contains(label)) return label;
    return null;
  }

  void _submitText() {
    final text = _textController.text;
    if (text.isEmpty) return;
    Navigator.pop(
      context,
      toolbarCustomActionId(text: text, appendEnter: _appendEnter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final canSave = _textMode
        ? _textController.text.isNotEmpty
        : _combo != null;

    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.initial == null
              ? t.toolbar.newCustomKey
              : t.toolbar.editCustomKey,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: _ModeTab(
                    label: t.toolbar.comboMode,
                    selected: !_textMode,
                    onTap: () => setState(() => _textMode = false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeTab(
                    label: t.toolbar.textMode,
                    selected: _textMode,
                    onTap: () => setState(() => _textMode = true),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _textMode ? _buildTextMode(t) : _buildComboMode(t)),
          _buildSaveBar(t, canSave),
        ],
      ),
    );
  }

  Widget _buildSaveBar(Translations t, bool canSave) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.surfaceBorder)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: !canSave
                ? null
                : (_textMode ? _submitText : _submitCombo),
            child: Text(t.common.save),
          ),
        ),
      ),
    );
  }

  /// The capture box is a field only in that it takes focus and raises the
  /// keyboard - the keystroke is captured, never typed into anything. The
  /// special/function key grid below it covers keys no soft keyboard can
  /// produce.
  Widget _buildComboMode(Translations t) {
    final combo = _combo;
    final preview =
        combo?.label ??
        '${comboModifierPrefix(ctrl: _ctrl, alt: _alt, shift: _shift)}${t.toolbar.comboAwaitingKey}';

    return KeyboardListener(
      focusNode: _keyboardFocus,
      onKeyEvent: _onHardwareKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              _ModifierChip(
                label: 'CTRL',
                selected: _ctrl,
                onTap: () => setState(() => _ctrl = !_ctrl),
              ),
              const SizedBox(width: 8),
              _ModifierChip(
                label: 'ALT',
                selected: _alt,
                onTap: () => setState(() => _alt = !_alt),
              ),
              const SizedBox(width: 8),
              _ModifierChip(
                label: 'SHIFT',
                selected: _shift,
                onTap: () => setState(() => _shift = !_shift),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _focusCapture,
            child: Container(
              height: 74,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.surfaceCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: _captureFocus.hasFocus
                      ? context.colors.primary
                      : context.colors.surfaceBorder,
                  width: _captureFocus.hasFocus ? 1.6 : 1,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 1,
                    height: 1,
                    child: TextField(
                      controller: _captureController,
                      focusNode: _captureFocus,
                      autofocus: true,
                      showCursor: false,
                      enableSuggestions: false,
                      autocorrect: false,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(
                        color: context.colors.surfaceCard.invisible,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: _onCaptureChanged,
                      onSubmitted: (_) {
                        _resetCaptureField();
                        _capture('cr');
                      },
                      onTapOutside: (_) {},
                    ),
                  ),
                  Text(
                    preview,
                    style: TextStyle(
                      color: combo == null
                          ? context.colors.textTertiary
                          : context.colors.primary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.toolbar.comboHint,
            style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Text(
            t.toolbar.comboSpecialKeys,
            style: TextStyle(
              color: context.colors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _keyGrid([...kComboSpecialKeys, ...kComboFunctionKeys]),
        ],
      ),
    );
  }

  Widget _keyGrid(List<String> keys) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final key in keys)
          _KeyChip(
            label: kToolbarActions[key]?.label ?? key.toUpperCase(),
            selected: _capturedKey == key,
            onTap: () => _capture(key),
          ),
      ],
    );
  }

  Widget _buildTextMode(Translations t) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          controller: _textController,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: t.toolbar.customTextHint,
            helperText: t.toolbar.customTextHelp,
            helperMaxLines: 2,
          ),
          onChanged: (_) => setState(() {}),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onSubmitted: (_) => _submitText(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.toolbar.customAppendEnter),
          subtitle: Text(
            t.toolbar.customAppendEnterSubtitle,
            style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
          ),
          value: _appendEnter,
          activeThumbColor: context.colors.primary,
          onChanged: (value) => setState(() => _appendEnter = value),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? context.colors.primary.withValues(alpha: 0.16)
          : context.colors.surfaceCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: selected
                  ? context.colors.primary
                  : context.colors.surfaceBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? context.colors.primary
                  : context.colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModifierChip extends StatelessWidget {
  const _ModifierChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.colors.primary : context.colors.surfaceCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: selected
                  ? context.colors.primary
                  : context.colors.surfaceBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? context.colors.backgroundPrimary
                  : context.colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
