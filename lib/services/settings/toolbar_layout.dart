import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'setting.dart';

/// Everything the special-keys toolbar is made of: the action table, the grid
/// configuration and their persistence.
///
/// The action table is the single source of truth for what a slot id means -
/// its label, the bytes it sends, whether it repeats. Both the toolbar and the
/// settings editor read it, so a key can never render one way and send
/// something else.

enum ToolbarActionKind {
  /// Sends a fixed byte sequence.
  bytes,

  /// A cursor key: the sequence depends on the shift state.
  arrow,

  /// Toggles ctrl/alt/shift rather than sending anything.
  modifier,

  /// Sends literal user-provided text.
  text,

  /// Runs a saved snippet.
  snippet,

  /// Dismisses the on-screen soft keyboard.
  dismissKeyboard,
}

enum ToolbarActionCategory {
  navigation,
  editing,
  modifiers,
  function,
  symbols,
  custom,
}

class ToolbarAction {
  const ToolbarAction({
    required this.id,
    required this.label,
    required this.kind,
    required this.category,
    this.bytes = const [],
    this.shiftBytes,
    this.arrowCode = 0,
    this.repeatable = false,
    this.payload,
    this.appendEnter = false,
  });

  final String id;
  final String label;
  final ToolbarActionKind kind;
  final ToolbarActionCategory category;
  final List<int> bytes;

  /// Sequence to send while shift is held. Null means shift does not change
  /// this key, and so must not be consumed by pressing it.
  final List<int>? shiftBytes;
  final int arrowCode;
  final bool repeatable;

  /// Literal text for [ToolbarActionKind.text], snippet id for
  /// [ToolbarActionKind.snippet].
  final String? payload;

  /// Custom text keys can end with a carriage return, which turns them from
  /// "type this" into "run this".
  final bool appendEnter;
}

const _esc = 0x1b;

ToolbarAction _key(
  String id,
  String label,
  List<int> bytes, {
  ToolbarActionCategory category = ToolbarActionCategory.editing,
  List<int>? shiftBytes,
  bool repeatable = false,
}) {
  return ToolbarAction(
    id: id,
    label: label,
    kind: ToolbarActionKind.bytes,
    category: category,
    bytes: bytes,
    shiftBytes: shiftBytes,
    repeatable: repeatable,
  );
}

ToolbarAction _symbol(String id, String char) {
  return ToolbarAction(
    id: id,
    label: char,
    kind: ToolbarActionKind.bytes,
    category: ToolbarActionCategory.symbols,
    bytes: utf8.encode(char),
    repeatable: true,
  );
}

ToolbarAction _arrow(String id, String label, int code) {
  return ToolbarAction(
    id: id,
    label: label,
    kind: ToolbarActionKind.arrow,
    category: ToolbarActionCategory.navigation,
    arrowCode: code,
    repeatable: true,
  );
}

ToolbarAction _modifier(String id, String label) {
  return ToolbarAction(
    id: id,
    label: label,
    kind: ToolbarActionKind.modifier,
    category: ToolbarActionCategory.modifiers,
  );
}

ToolbarAction _fnKey(int number, List<int> bytes) {
  return ToolbarAction(
    id: 'f$number',
    label: 'F$number',
    kind: ToolbarActionKind.bytes,
    category: ToolbarActionCategory.function,
    bytes: bytes,
  );
}

/// Every built-in action, keyed by slot id.
final Map<String, ToolbarAction> kToolbarActions = {
  for (final action in _builtinActions) action.id: action,
};

/// Every built-in action, grouped by category. Symbols get their own entries
/// because they are buried behind layers on most soft keyboards.
final List<ToolbarAction> _builtinActions = [
  _arrow('arrow_left', '←', 0x44),
  _arrow('arrow_up', '↑', 0x41),
  _arrow('arrow_down', '↓', 0x42),
  _arrow('arrow_right', '→', 0x43),
  _key(
    'home',
    'HOME',
    [_esc, 0x5b, 0x48],
    category: ToolbarActionCategory.navigation,
    shiftBytes: [_esc, 0x5b, 0x31, 0x3b, 0x32, 0x48],
  ),
  _key(
    'end',
    'END',
    [_esc, 0x5b, 0x46],
    category: ToolbarActionCategory.navigation,
    shiftBytes: [_esc, 0x5b, 0x31, 0x3b, 0x32, 0x46],
  ),
  _key(
    'page_up',
    'PAGE↑',
    [_esc, 0x5b, 0x35, 0x7e],
    category: ToolbarActionCategory.navigation,
    shiftBytes: [_esc, 0x5b, 0x35, 0x3b, 0x32, 0x7e],
    repeatable: true,
  ),
  _key(
    'page_down',
    'PAGE↓',
    [_esc, 0x5b, 0x36, 0x7e],
    category: ToolbarActionCategory.navigation,
    shiftBytes: [_esc, 0x5b, 0x36, 0x3b, 0x32, 0x7e],
    repeatable: true,
  ),

  _key('esc', 'ESC', [_esc]),
  _key('tab', 'TAB', [0x09], shiftBytes: [_esc, 0x5b, 0x5a]),
  _key('s_tab', 'S+TAB', [_esc, 0x5b, 0x5a]),
  _key('cr', 'CR', [0x0d]),
  _key('del', 'DEL', [_esc, 0x5b, 0x33, 0x7e], repeatable: true),
  _key('backspace', 'BKSP', [0x7f], repeatable: true),
  _key('insert', 'INSERT', [_esc, 0x5b, 0x32, 0x7e]),
  _key('space', 'SPACE', [0x20], repeatable: true),
  const ToolbarAction(
    id: 'hide_keyboard',
    label: '▼',
    kind: ToolbarActionKind.dismissKeyboard,
    category: ToolbarActionCategory.editing,
  ),

  _modifier('ctrl', 'CTRL'),
  _modifier('alt', 'ALT'),
  _modifier('shift', 'SHIFT'),

  _fnKey(1, [_esc, 0x4f, 0x50]),
  _fnKey(2, [_esc, 0x4f, 0x51]),
  _fnKey(3, [_esc, 0x4f, 0x52]),
  _fnKey(4, [_esc, 0x4f, 0x53]),
  _fnKey(5, [_esc, 0x5b, 0x31, 0x35, 0x7e]),
  _fnKey(6, [_esc, 0x5b, 0x31, 0x37, 0x7e]),
  _fnKey(7, [_esc, 0x5b, 0x31, 0x38, 0x7e]),
  _fnKey(8, [_esc, 0x5b, 0x31, 0x39, 0x7e]),
  _fnKey(9, [_esc, 0x5b, 0x32, 0x30, 0x7e]),
  _fnKey(10, [_esc, 0x5b, 0x32, 0x31, 0x7e]),
  _fnKey(11, [_esc, 0x5b, 0x32, 0x33, 0x7e]),
  _fnKey(12, [_esc, 0x5b, 0x32, 0x34, 0x7e]),

  _symbol('sym_slash', '/'),
  _symbol('sym_backslash', r'\'),
  _symbol('sym_pipe', '|'),
  _symbol('sym_tilde', '~'),
  _symbol('sym_minus', '-'),
  _symbol('sym_underscore', '_'),
  _symbol('sym_dollar', r'$'),
  _symbol('sym_asterisk', '*'),
  _symbol('sym_ampersand', '&'),
  _symbol('sym_caret', '^'),
  _symbol('sym_percent', '%'),
  _symbol('sym_hash', '#'),
  _symbol('sym_bang', '!'),
  _symbol('sym_question', '?'),
  _symbol('sym_colon', ':'),
  _symbol('sym_semicolon', ';'),
  _symbol('sym_dquote', '"'),
  _symbol('sym_quote', "'"),
  _symbol('sym_backtick', '`'),
  _symbol('sym_lparen', '('),
  _symbol('sym_rparen', ')'),
  _symbol('sym_lbracket', '['),
  _symbol('sym_rbracket', ']'),
  _symbol('sym_lbrace', '{'),
  _symbol('sym_rbrace', '}'),
  _symbol('sym_lt', '<'),
  _symbol('sym_gt', '>'),
  _symbol('sym_equals', '='),
  _symbol('sym_plus', '+'),
  _symbol('sym_at', '@'),
  _symbol('sym_dot', '.'),
  _symbol('sym_comma', ','),
];

/// Ids of every built-in action, in table order.
final List<String> kAllBuiltinIds = kToolbarActions.keys.toList();

/// Legacy self-contained text key: the text, URI-encoded. Still read so keys
/// saved before custom keys grew a label survive.
const String kToolbarTextPrefix = 'text:';

/// A custom key: base64 of `{"t": text, "l": label, "e": appendEnter}`. The
/// definition rides along inside the id, so a slot (or an export file) never
/// depends on a lookup table that could go missing.
const String kToolbarCustomPrefix = 'custom:';

/// A modifier combo, e.g. `combo:c:r` for Ctrl+R or `combo:ca:arrow_left` for
/// Ctrl+Alt+Left. Built by tapping the modifiers and then the key, so it needs
/// no name of its own.
const String kToolbarComboPrefix = 'combo:';
const String kToolbarSnippetPrefix = 'snippet:';

/// US-layout shifted forms of the printable ASCII keys.
const Map<int, int> kShiftedAsciiSymbols = {
  0x31: 0x21,
  0x32: 0x40,
  0x33: 0x23,
  0x34: 0x24,
  0x35: 0x25,
  0x36: 0x5e,
  0x37: 0x26,
  0x38: 0x2a,
  0x39: 0x28,
  0x30: 0x29,
  0x2d: 0x5f,
  0x3d: 0x2b,
  0x5b: 0x7b,
  0x5d: 0x7d,
  0x5c: 0x7c,
  0x3b: 0x3a,
  0x27: 0x22,
  0x2c: 0x3c,
  0x2e: 0x3e,
  0x2f: 0x3f,
  0x60: 0x7e,
};

/// The shifted form of [byte] (a-z to A-Z, or a lookup in
/// [kShiftedAsciiSymbols]), or null when shift leaves it alone.
int? shiftedAsciiByte(int byte) {
  if (byte >= 0x61 && byte <= 0x7a) return byte - 32;
  return kShiftedAsciiSymbols[byte];
}

/// Base keys a combo can be built on, in the order the builder lays them out.
const List<String> kComboLetterKeys = [
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', //
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
];

const List<String> kComboDigitKeys = [
  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', //
];

const List<String> kComboSpecialKeys = [
  'tab',
  'cr',
  'esc',
  'space',
  'backspace',
  'del',
  'insert',
  'home',
  'end',
  'page_up',
  'page_down',
  'arrow_left',
  'arrow_down',
  'arrow_up',
  'arrow_right',
];

const List<String> kComboFunctionKeys = [
  'f1', 'f2', 'f3', 'f4', 'f5', 'f6', //
  'f7', 'f8', 'f9', 'f10', 'f11', 'f12',
];

/// Keys whose modified form is `CSI 1 ; <mod> <final>`.
const Map<String, int> _comboCsiFinals = {
  'arrow_up': 0x41,
  'arrow_down': 0x42,
  'arrow_right': 0x43,
  'arrow_left': 0x44,
  'end': 0x46,
  'home': 0x48,
  'f1': 0x50,
  'f2': 0x51,
  'f3': 0x52,
  'f4': 0x53,
};

/// Keys whose modified form is `CSI <n> ; <mod> ~`.
const Map<String, int> _comboCsiNumbers = {
  'insert': 2,
  'del': 3,
  'page_up': 5,
  'page_down': 6,
  'f5': 15,
  'f6': 17,
  'f7': 18,
  'f8': 19,
  'f9': 20,
  'f10': 21,
  'f11': 23,
  'f12': 24,
};

const Map<String, int> _comboSimpleBytes = {
  'tab': 0x09,
  'cr': 0x0d,
  'esc': 0x1b,
  'space': 0x20,
  'backspace': 0x7f,
};

/// Terminal names, not Mac symbols: `⌥` reads as Option to anyone who knows it.
String comboModifierPrefix({
  required bool ctrl,
  required bool alt,
  required bool shift,
}) => '${ctrl ? 'Ctrl+' : ''}${alt ? 'Alt+' : ''}${shift ? 'Shift+' : ''}';

class ToolbarCombo {
  const ToolbarCombo({
    required this.key,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
  });

  final String key;
  final bool ctrl;
  final bool alt;
  final bool shift;

  bool get hasModifier => ctrl || alt || shift;

  /// xterm's modifier parameter: 1 plus a bit per held modifier.
  int get modifierCode => 1 + (shift ? 1 : 0) + (alt ? 2 : 0) + (ctrl ? 4 : 0);

  String get label {
    final base = kToolbarActions[key]?.label ?? key.toUpperCase();
    return '${comboModifierPrefix(ctrl: ctrl, alt: alt, shift: shift)}$base';
  }

  /// The byte sequence this combo sends.
  ///
  /// Shift+Tab has its own sequence rather than a modifier parameter.
  List<int> get bytes {
    final finalByte = _comboCsiFinals[key];
    if (finalByte != null) {
      return [
        0x1b,
        0x5b,
        0x31,
        0x3b,
        ...ascii.encode('$modifierCode'),
        finalByte,
      ];
    }
    final number = _comboCsiNumbers[key];
    if (number != null) {
      return [
        0x1b,
        0x5b,
        ...ascii.encode('$number'),
        0x3b,
        ...ascii.encode('$modifierCode'),
        0x7e,
      ];
    }
    if (key == 'tab' && shift) {
      return [if (alt) 0x1b, 0x1b, 0x5b, 0x5a];
    }

    var byte =
        _comboSimpleBytes[key] ?? (key.length == 1 ? key.codeUnitAt(0) : null);
    if (byte == null) return const [];
    if (shift) byte = shiftedAsciiByte(byte) ?? byte;
    if (ctrl) byte &= 0x1f;
    return [if (alt) 0x1b, byte];
  }
}

/// Whether [key] names a key a combo can be built on: any printable ASCII
/// character (whatever the keyboard produced) or one of the named keys.
bool isComboKeyToken(String key) {
  if (key.length == 1) {
    final code = key.codeUnitAt(0);
    return code >= 0x20 && code <= 0x7e;
  }
  return kComboSpecialKeys.contains(key) || kComboFunctionKeys.contains(key);
}

/// Turns a typed character into a combo: an uppercase letter (or a shifted
/// symbol) is stored as its unshifted key plus shift.
ToolbarCombo comboFromTypedCharacter(
  String character, {
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
}) {
  if (character.isEmpty) return ToolbarCombo(key: '', ctrl: ctrl, alt: alt);
  final code = character.codeUnitAt(0);
  if (code >= 0x41 && code <= 0x5a) {
    return ToolbarCombo(
      key: String.fromCharCode(code + 32),
      ctrl: ctrl,
      alt: alt,
      shift: true,
    );
  }
  for (final entry in kShiftedAsciiSymbols.entries) {
    if (entry.value == code) {
      return ToolbarCombo(
        key: String.fromCharCode(entry.key),
        ctrl: ctrl,
        alt: alt,
        shift: true,
      );
    }
  }
  if (code == 0x20) {
    return ToolbarCombo(key: 'space', ctrl: ctrl, alt: alt, shift: shift);
  }
  return ToolbarCombo(key: character, ctrl: ctrl, alt: alt, shift: shift);
}

/// Builds the slot id for a modifier combo. With no modifiers held, a key that
/// already exists on its own is returned as that built-in instead of a new
/// custom key.
String toolbarComboActionId(ToolbarCombo combo) {
  if (!combo.hasModifier && kToolbarActions.containsKey(combo.key)) {
    return combo.key;
  }
  final mods =
      '${combo.ctrl ? 'c' : ''}${combo.alt ? 'a' : ''}${combo.shift ? 's' : ''}';
  return '$kToolbarComboPrefix$mods:${combo.key}';
}

/// Reads a combo back out of [id], or null when it is not a combo id.
ToolbarCombo? parseToolbarComboId(String id) {
  if (!id.startsWith(kToolbarComboPrefix)) return null;
  final body = id.substring(kToolbarComboPrefix.length);
  final split = body.indexOf(':');
  if (split == -1) return null;
  final mods = body.substring(0, split);
  final key = body.substring(split + 1);
  if (key.isEmpty) return null;
  if (!isComboKeyToken(key)) return null;
  return ToolbarCombo(
    key: key,
    ctrl: mods.contains('c'),
    alt: mods.contains('a'),
    shift: mods.contains('s'),
  );
}

/// Builds the slot id for a custom key.
String toolbarCustomActionId({
  required String text,
  String label = '',
  bool appendEnter = false,
}) {
  final payload = jsonEncode({
    't': text,
    if (label.trim().isNotEmpty) 'l': label.trim(),
    if (appendEnter) 'e': true,
  });
  return '$kToolbarCustomPrefix${base64Url.encode(utf8.encode(payload))}';
}

/// Builds the slot id for a snippet button.
String toolbarSnippetActionId(String snippetId) =>
    '$kToolbarSnippetPrefix$snippetId';

/// Builds the [ToolbarAction] a custom key resolves to.
///
/// Not repeatable when it appends Enter: holding down a key that fires a
/// command should not run that command over and over.
ToolbarAction _customAction({
  required String id,
  required String text,
  required String label,
  required bool appendEnter,
}) {
  return ToolbarAction(
    id: id,
    label: label.isNotEmpty ? label : text,
    kind: ToolbarActionKind.text,
    category: ToolbarActionCategory.custom,
    bytes: [...utf8.encode(text), if (appendEnter) 0x0d],
    payload: text,
    appendEnter: appendEnter,
    repeatable: !appendEnter,
  );
}

/// Resolves [id] to an action, including the dynamic custom/snippet forms.
/// Returns null for ids this build does not know.
///
/// Ctrl combos used to be their own built-ins (`ctrl_a` and the like); they
/// are built interactively now, but ids already sitting in a slot keep
/// working.
ToolbarAction? toolbarActionForId(String id) {
  if (id.isEmpty) return null;
  final builtin = kToolbarActions[id];
  if (builtin != null) return builtin;

  if (id.startsWith(kToolbarCustomPrefix)) {
    final raw = id.substring(kToolbarCustomPrefix.length);
    if (raw.isEmpty) return null;
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(raw)))
              as Map<String, dynamic>;
      final text = decoded['t'] as String? ?? '';
      if (text.isEmpty) return null;
      return _customAction(
        id: id,
        text: text,
        label: decoded['l'] as String? ?? '',
        appendEnter: decoded['e'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  if (id.startsWith(kToolbarTextPrefix)) {
    final raw = id.substring(kToolbarTextPrefix.length);
    if (raw.isEmpty) return null;
    String text;
    try {
      text = Uri.decodeComponent(raw);
    } on FormatException {
      return null;
    }
    if (text.isEmpty) return null;
    return _customAction(id: id, text: text, label: '', appendEnter: false);
  }

  if (id.startsWith('ctrl_') && id.length == 6) {
    final letter = id.substring(5);
    if (kComboLetterKeys.contains(letter)) {
      final legacy = ToolbarCombo(key: letter, ctrl: true);
      return ToolbarAction(
        id: id,
        label: legacy.label,
        kind: ToolbarActionKind.bytes,
        category: ToolbarActionCategory.custom,
        bytes: legacy.bytes,
        payload: letter,
        repeatable: true,
      );
    }
  }

  final combo = parseToolbarComboId(id);
  if (combo != null) {
    final bytes = combo.bytes;
    if (bytes.isEmpty) return null;
    return ToolbarAction(
      id: id,
      label: combo.label,
      kind: ToolbarActionKind.bytes,
      category: ToolbarActionCategory.custom,
      bytes: bytes,
      payload: combo.key,
      repeatable: true,
    );
  }

  if (id.startsWith(kToolbarSnippetPrefix)) {
    final snippetId = id.substring(kToolbarSnippetPrefix.length);
    if (snippetId.isEmpty) return null;
    return ToolbarAction(
      id: id,
      label: '⌘',
      kind: ToolbarActionKind.snippet,
      category: ToolbarActionCategory.custom,
      payload: snippetId,
    );
  }

  return null;
}

bool isValidToolbarActionId(String id) => toolbarActionForId(id) != null;

/// Trims a label down to what still reads on a toolbar key - custom text and
/// snippet names are arbitrarily long.
String shortToolbarLabel(String value) =>
    value.length <= 10 ? value : '${value.substring(0, 9)}…';

const kToolbarCustomKeysPrefsKey = 'terminal_toolbar_custom_keys';

/// Custom keys the user has made, whether or not they sit in a slot right now.
/// This is what the settings pool lists them from, so one can be built once and
/// moved around (or reused on another page) later.
final Setting<List<String>> toolbarCustomKeysSetting = Setting<List<String>>(
  key: kToolbarCustomKeysPrefsKey,
  fallback: const [],
  read: (preferences) =>
      (preferences.getStringList(kToolbarCustomKeysPrefsKey) ?? const [])
          .where(isValidToolbarActionId)
          .toList(),
  write: (preferences, value) {
    final unique = <String>[];
    for (final id in value) {
      if (isValidToolbarActionId(id) && !unique.contains(id)) unique.add(id);
    }
    return preferences.setStringList(kToolbarCustomKeysPrefsKey, unique);
  },
);

/// Writes [ids] as the custom-key library.
///
/// The write drops duplicates and anything that no longer parses, so what
/// ends up in memory has to come back from the reader rather than from what
/// was handed in.
Future<void> saveToolbarCustomKeys(List<String> ids) async {
  await toolbarCustomKeysSetting.set(ids);
  await toolbarCustomKeysSetting.load();
}

Future<void> addToolbarCustomKey(String id) =>
    saveToolbarCustomKeys([...toolbarCustomKeysSetting.value, id]);

/// Puts [mapSlot] through every stored layout - every profile's and the live
/// toolbar's.
///
/// A custom key belongs to the whole app, not to one layout, so editing or
/// deleting one has to reach the profiles that are not open. Touching only the
/// live layout left every other profile holding an id nothing answers to.
Future<void> _rewriteEveryToolbarLayout(String Function(String) mapSlot) async {
  final profiles = toolbarSettings.profiles.value;
  var next = profiles;
  for (final profile in profiles.profiles) {
    final order = [for (final slot in profile.layout.order) mapSlot(slot)];
    if (listEquals(order, profile.layout.order)) continue;
    next = next.withProfile(
      profile.copyWith(layout: profile.layout.copyWith(order: order)),
    );
  }
  if (next != profiles) await saveToolbarProfiles(next);
  final layout = toolbarSettings.layout.value;
  final order = [for (final slot in layout.order) mapSlot(slot)];
  if (!listEquals(order, layout.order)) {
    await saveToolbarLayout(layout.copyWith(order: order));
  }
}

/// Deletes [id] from the custom-key library and clears it out of every slot
/// it sits in - a slot still holding it would keep working, but the user just
/// said they don't want the key any more.
Future<void> removeToolbarCustomKey(String id) async {
  await saveToolbarCustomKeys(
    toolbarCustomKeysSetting.value.where((key) => key != id).toList(),
  );
  await _rewriteEveryToolbarLayout((slot) => slot == id ? '' : slot);
}

/// Swaps an edited custom key in place, both in the library and in whatever
/// slot it already occupies.
Future<void> replaceToolbarCustomKey(String oldId, String newId) async {
  if (oldId == newId) return;
  await saveToolbarCustomKeys([
    for (final key in toolbarCustomKeysSetting.value)
      key == oldId ? newId : key,
  ]);
  await _rewriteEveryToolbarLayout((slot) => slot == oldId ? newId : slot);
}

const kToolbarOrderPrefsKey = 'terminal_toolbar_order_v2';
const kToolbarColumnsPrefsKey = 'terminal_toolbar_columns';
const kToolbarRowsPrefsKey = 'terminal_toolbar_rows';
const kToolbarPagesPrefsKey = 'terminal_toolbar_pages';
const kToolbarButtonHeightPrefsKey = 'terminal_toolbar_button_height';
const kToolbarEnabledPrefsKey = 'terminal_toolbar_enabled';

const int kToolbarLayoutCount = 2;
const int kToolbarColumns = 5;
const int kToolbarRows = 2;
const int kToolbarSlotsPerLayout = kToolbarColumns * kToolbarRows;
const int kToolbarSlotCount = kToolbarLayoutCount * kToolbarSlotsPerLayout;
const double kToolbarButtonHeight = 37;

const int kToolbarMinColumns = 4;
const int kToolbarMaxColumns = 8;
const int kToolbarMinRows = 1;
const int kToolbarMaxRows = 4;
const int kToolbarMinPages = 1;
const int kToolbarMaxPages = 5;
const double kToolbarMinButtonHeight = 28;
const double kToolbarMaxButtonHeight = 56;

const List<String> kDefaultToolbarOrder = [
  'esc',
  'home',
  'end',
  'ctrl',
  'alt',
  'tab',
  'arrow_left',
  'arrow_up',
  'arrow_down',
  'arrow_right',
  's_tab',
  'cr',
  'shift',
  'del',
  'backspace',
  'page_up',
  'page_down',
  'f1',
  'f2',
  'f3',
];

const kToolbarProfilesPrefsKey = 'terminal_toolbar_profiles_v1';
const kToolbarActiveProfilePrefsKey = 'terminal_toolbar_active_profile';

/// The profile every install starts with, and the one an upgrade's existing
/// layout is carried into.
const kDefaultToolbarProfileId = 'default';

/// One named toolbar layout.
///
/// A profile is the whole grid, shape included - a layout for writing code and
/// one for reading logs do not want the same number of rows, so switching
/// between them has to bring the shape along or half the point is lost.
@immutable
class ToolbarProfile {
  const ToolbarProfile({
    required this.id,
    required this.name,
    required this.layout,
  });

  final String id;

  /// Empty on the seeded profile, which the UI names in the user's language
  /// rather than storing an English word on their device.
  final String name;

  final ToolbarLayout layout;

  bool get isDefault => id == kDefaultToolbarProfileId;

  @override
  bool operator ==(Object other) =>
      other is ToolbarProfile &&
      other.id == id &&
      other.name == name &&
      other.layout == layout;

  @override
  int get hashCode => Object.hash(id, name, layout);

  ToolbarProfile copyWith({String? name, ToolbarLayout? layout}) =>
      ToolbarProfile(
        id: id,
        name: name ?? this.name,
        layout: layout ?? this.layout,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'order': layout.order,
    'columns': layout.columns,
    'rows': layout.rows,
    'pages': layout.pages,
    'buttonHeight': layout.buttonHeight,
  };

  static ToolbarProfile? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final columns = _clampInt(
      (json['columns'] as num?)?.toInt() ?? kToolbarColumns,
      kToolbarMinColumns,
      kToolbarMaxColumns,
    );
    final rows = _clampInt(
      (json['rows'] as num?)?.toInt() ?? kToolbarRows,
      kToolbarMinRows,
      kToolbarMaxRows,
    );
    final pages = _clampInt(
      (json['pages'] as num?)?.toInt() ?? kToolbarLayoutCount,
      kToolbarMinPages,
      kToolbarMaxPages,
    );
    return ToolbarProfile(
      id: id,
      name: json['name'] as String? ?? '',
      layout: ToolbarLayout(
        order: normalizeToolbarOrder(
          (json['order'] as List<dynamic>?)?.whereType<String>().toList() ??
              const [],
          slotCount: columns * rows * pages,
        ),
        columns: columns,
        rows: rows,
        pages: pages,
        buttonHeight:
            ((json['buttonHeight'] as num?)?.toDouble() ?? kToolbarButtonHeight)
                .clamp(kToolbarMinButtonHeight, kToolbarMaxButtonHeight)
                .toDouble(),
      ),
    );
  }
}

/// Every saved layout plus which one the toolbar is currently drawing.
///
/// The two are one value because they are not independent: an [activeId] that
/// names no profile is a toolbar with nothing to draw, so it is resolved on
/// the way in rather than guarded at every read.
@immutable
class ToolbarProfiles {
  ToolbarProfiles({required List<ToolbarProfile> profiles, String? activeId})
    : profiles = List.unmodifiable(
        profiles.isEmpty
            ? [
                ToolbarProfile(
                  id: kDefaultToolbarProfileId,
                  name: '',
                  layout: ToolbarLayout.defaults,
                ),
              ]
            : profiles,
      ),
      activeId = profiles.any((profile) => profile.id == activeId)
          ? activeId!
          : (profiles.isEmpty ? kDefaultToolbarProfileId : profiles.first.id);

  final List<ToolbarProfile> profiles;
  final String activeId;

  ToolbarProfile get active => profiles.firstWhere(
    (p) => p.id == activeId,
    orElse: () => profiles.first,
  );

  ToolbarProfiles withProfile(ToolbarProfile profile) => ToolbarProfiles(
    profiles: [
      for (final existing in profiles)
        if (existing.id == profile.id) profile else existing,
    ],
    activeId: activeId,
  );

  ToolbarProfiles added(ToolbarProfile profile, {bool activate = true}) =>
      ToolbarProfiles(
        profiles: [...profiles, profile],
        activeId: activate ? profile.id : activeId,
      );

  /// Drops [id], unless it is the only profile left - a toolbar with no layout
  /// has nothing to fall back to.
  ToolbarProfiles removed(String id) {
    if (profiles.length <= 1) return this;
    final remaining = [
      for (final profile in profiles)
        if (profile.id != id) profile,
    ];
    return ToolbarProfiles(
      profiles: remaining,
      activeId: id == activeId ? remaining.first.id : activeId,
    );
  }

  ToolbarProfiles activated(String id) =>
      ToolbarProfiles(profiles: profiles, activeId: id);

  @override
  bool operator ==(Object other) =>
      other is ToolbarProfiles &&
      other.activeId == activeId &&
      listEquals(other.profiles, profiles);

  @override
  int get hashCode => Object.hash(activeId, Object.hashAll(profiles));
}

/// The toolbar grid: which action sits in which slot, and how the slots are
/// arranged.
@immutable
class ToolbarLayout {
  const ToolbarLayout({
    required this.order,
    this.columns = kToolbarColumns,
    this.rows = kToolbarRows,
    this.pages = kToolbarLayoutCount,
    this.buttonHeight = kToolbarButtonHeight,
  });

  final List<String> order;
  final int columns;
  final int rows;
  final int pages;
  final double buttonHeight;

  int get slotsPerPage => columns * rows;
  int get slotCount => slotsPerPage * pages;

  List<String> pageIds(int page) {
    final start = page * slotsPerPage;
    return List<String>.generate(
      slotsPerPage,
      (i) => (start + i) < order.length ? order[start + i] : '',
    );
  }

  bool isPageEmpty(int page) => pageIds(page).every((id) => id.isEmpty);

  /// Pages with at least one key on them. Always keeps the first page so the
  /// toolbar never collapses to nothing.
  List<int> get visiblePages {
    final visible = [
      for (int p = 0; p < pages; p++)
        if (!isPageEmpty(p)) p,
    ];
    return visible.isEmpty ? const [0] : visible;
  }

  ToolbarLayout copyWith({
    List<String>? order,
    int? columns,
    int? rows,
    int? pages,
    double? buttonHeight,
  }) {
    return ToolbarLayout(
      order: order ?? this.order,
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      pages: pages ?? this.pages,
      buttonHeight: buttonHeight ?? this.buttonHeight,
    );
  }

  /// How many keys [resized] would throw away for the given grid.
  ///
  /// Shrinking silently used to cost the user half a layout with no way back,
  /// so the editor asks first - and asking needs a number to put in front of
  /// them, worked out the same way the reflow does it.
  int keysLostByResize({int? columns, int? rows, int? pages}) {
    final before = order.where((id) => id.isNotEmpty).length;
    final after = resized(
      columns: columns,
      rows: rows,
      pages: pages,
    ).order.where((id) => id.isNotEmpty).length;
    return before - after;
  }

  /// Reflows [order] into a new grid, keeping each page's keys on their page
  /// and dropping whatever no longer fits.
  ToolbarLayout resized({int? columns, int? rows, int? pages}) {
    final next = ToolbarLayout(
      order: const [],
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      pages: pages ?? this.pages,
      buttonHeight: buttonHeight,
    );
    final reflowed = <String>[];
    for (int page = 0; page < next.pages; page++) {
      final kept = page < this.pages
          ? pageIds(page).where((id) => id.isNotEmpty).toList()
          : <String>[];
      for (int slot = 0; slot < next.slotsPerPage; slot++) {
        reflowed.add(slot < kept.length ? kept[slot] : '');
      }
    }
    return next.copyWith(order: reflowed);
  }

  static ToolbarLayout get defaults =>
      ToolbarLayout(order: List<String>.from(kDefaultToolbarOrder));

  /// The default grid with nothing in it, for a layout built from scratch.
  static ToolbarLayout get blank =>
      ToolbarLayout(order: List<String>.filled(kToolbarSlotCount, ''));

  @override
  bool operator ==(Object other) =>
      other is ToolbarLayout &&
      listEquals(other.order, order) &&
      other.columns == columns &&
      other.rows == rows &&
      other.pages == pages &&
      other.buttonHeight == buttonHeight;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(order), columns, rows, pages, buttonHeight);
}

/// Drops unknown and duplicate ids, keeps blanks, and pads to [slotCount].
List<String> normalizeToolbarOrder(
  List<String> order, {
  int slotCount = kToolbarSlotCount,
}) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final id in order) {
    if (normalized.length >= slotCount) break;
    if (id.isEmpty) {
      normalized.add('');
    } else if (isValidToolbarActionId(id) && seen.add(id)) {
      normalized.add(id);
    }
  }
  while (normalized.length < slotCount) {
    final fallback = normalized.length < kDefaultToolbarOrder.length
        ? kDefaultToolbarOrder[normalized.length]
        : '';
    if (fallback.isEmpty || seen.add(fallback)) {
      normalized.add(fallback);
    } else {
      normalized.add('');
    }
  }
  return normalized.take(slotCount).toList();
}

int _clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

/// The layout held in the five legacy grid keys - what the toolbar draws, and
/// what an install from before profiles existed is carried over from.
ToolbarLayout _readStoredLayout(SharedPreferences preferences) {
  final columns = _clampInt(
    preferences.getInt(kToolbarColumnsPrefsKey) ?? kToolbarColumns,
    kToolbarMinColumns,
    kToolbarMaxColumns,
  );
  final rows = _clampInt(
    preferences.getInt(kToolbarRowsPrefsKey) ?? kToolbarRows,
    kToolbarMinRows,
    kToolbarMaxRows,
  );
  final pages = _clampInt(
    preferences.getInt(kToolbarPagesPrefsKey) ?? kToolbarLayoutCount,
    kToolbarMinPages,
    kToolbarMaxPages,
  );
  final buttonHeight =
      (preferences.getDouble(kToolbarButtonHeightPrefsKey) ??
              kToolbarButtonHeight)
          .clamp(kToolbarMinButtonHeight, kToolbarMaxButtonHeight);
  return ToolbarLayout(
    order: normalizeToolbarOrder(
      preferences.getStringList(kToolbarOrderPrefsKey) ?? kDefaultToolbarOrder,
      slotCount: columns * rows * pages,
    ),
    columns: columns,
    rows: rows,
    pages: pages,
    buttonHeight: buttonHeight.toDouble(),
  );
}

/// The toolbar's persisted state: the grid and the custom keys that can be
/// placed in it.
///
/// The grid is one [Setting] rather than five, because its five stored keys
/// are not independent - `order` has to be normalised against
/// `columns * rows * pages`, so writing them separately would leave the
/// layout inconsistent between the writes.
class ToolbarSettings {
  ToolbarSettings._();

  static final ToolbarSettings instance = ToolbarSettings._();

  /// The active grid. Described for analytics by its shape only
  /// (`columns x rows x pages`) - which keys are in which slot is not
  /// something analytics has any use for. Dimensions can arrive from an
  /// import file, so the writer clamps them here rather than trusting them.
  final layout = Setting<ToolbarLayout>(
    key: kToolbarOrderPrefsKey,
    fallback: ToolbarLayout.defaults,
    describe: (value) => '${value.columns}x${value.rows}x${value.pages}',
    read: _readStoredLayout,
    write: (preferences, value) async {
      final clamped = value.copyWith(
        columns: _clampInt(
          value.columns,
          kToolbarMinColumns,
          kToolbarMaxColumns,
        ),
        rows: _clampInt(value.rows, kToolbarMinRows, kToolbarMaxRows),
        pages: _clampInt(value.pages, kToolbarMinPages, kToolbarMaxPages),
        buttonHeight: value.buttonHeight
            .clamp(kToolbarMinButtonHeight, kToolbarMaxButtonHeight)
            .toDouble(),
      );
      await preferences.setStringList(
        kToolbarOrderPrefsKey,
        normalizeToolbarOrder(clamped.order, slotCount: clamped.slotCount),
      );
      await preferences.setInt(kToolbarColumnsPrefsKey, clamped.columns);
      await preferences.setInt(kToolbarRowsPrefsKey, clamped.rows);
      await preferences.setInt(kToolbarPagesPrefsKey, clamped.pages);
      await preferences.setDouble(
        kToolbarButtonHeightPrefsKey,
        clamped.buttonHeight,
      );
    },
  );

  /// Every saved layout and which one is in use.
  ///
  /// One setting over two stored keys, for the same reason [layout] is one
  /// over five: an active id that names no profile is not a state the rest of
  /// the app should have to defend against.
  ///
  /// [layout] stays the active layout, written alongside this whenever a
  /// profile is edited or switched to. That is a copy, deliberately: the live
  /// toolbar reads [layout] on every frame it paints, and nothing about
  /// drawing a toolbar should have to know that profiles exist. Every write
  /// goes through [saveToolbarLayout] or [activateToolbarProfile], which keep
  /// the two in step.
  ///
  /// On first run after profiles landed, or a store that read back as
  /// nothing, whatever the toolbar looks like right now becomes the profile
  /// the user already has, rather than a default that quietly replaces it. An
  /// unreadable stored entry is skipped rather than failing the whole read,
  /// so it does not cost the user every other layout.
  final profiles = Setting<ToolbarProfiles>(
    key: kToolbarProfilesPrefsKey,
    fallback: ToolbarProfiles(profiles: const []),
    describe: (value) => value.profiles.length,
    read: (preferences) {
      ToolbarProfiles seededFromLayout() => ToolbarProfiles(
        profiles: [
          ToolbarProfile(
            id: kDefaultToolbarProfileId,
            name: '',
            layout: _readStoredLayout(preferences),
          ),
        ],
      );

      final raw = preferences.getStringList(kToolbarProfilesPrefsKey);
      if (raw == null || raw.isEmpty) return seededFromLayout();
      final stored = <ToolbarProfile>[];
      for (final entry in raw) {
        try {
          final profile = ToolbarProfile.fromJson(
            jsonDecode(entry) as Map<String, dynamic>,
          );
          if (profile != null) stored.add(profile);
        } catch (_) {}
      }
      if (stored.isEmpty) return seededFromLayout();
      return ToolbarProfiles(
        profiles: stored,
        activeId: preferences.getString(kToolbarActiveProfilePrefsKey),
      );
    },
    write: (preferences, value) async {
      await preferences.setStringList(kToolbarProfilesPrefsKey, [
        for (final profile in value.profiles) jsonEncode(profile.toJson()),
      ]);
      await preferences.setString(
        kToolbarActiveProfilePrefsKey,
        value.activeId,
      );
    },
  );

  Setting<List<String>> get customKeys => toolbarCustomKeysSetting;

  /// Whether the toolbar is drawn over a session at all.
  ///
  /// Watched by the terminal, so switching it off reaches an open session
  /// without it having to be reopened. Off means the rows it took go back to
  /// the terminal - the layout is kept, not cleared, so switching it on again
  /// brings the same keys back.
  final enabled = Setting.boolean(kToolbarEnabledPrefsKey, fallback: true);

  Future<void> load() async {
    await Future.wait([
      layout.load(),
      profiles.load(),
      customKeys.load(),
      enabled.load(),
    ]);
  }
}

ToolbarSettings get toolbarSettings => ToolbarSettings.instance;

/// Writes the toolbar's layout, and with it the profile that layout belongs
/// to.
///
/// Every path that changes the grid comes through here - the editor, the
/// import file - so the active profile cannot fall behind what the toolbar is
/// drawing without something else going wrong first.
///
/// Clamping and normalisation happen inside the write, so the value kept in
/// memory has to come back from the reader, not from what was handed in.
Future<void> saveToolbarLayout(ToolbarLayout layout) async {
  await toolbarSettings.layout.set(layout);
  final stored = await toolbarSettings.layout.load();
  final profiles = toolbarSettings.profiles.value;
  final active = profiles.active;
  if (active.layout == stored) return;
  await toolbarSettings.profiles.set(
    profiles.withProfile(active.copyWith(layout: stored)),
  );
}

Future<void> saveToolbarProfiles(ToolbarProfiles profiles) async {
  await toolbarSettings.profiles.set(profiles);
}

/// The bounds [ToolbarSettings.layout] enforces on write, as a plain function.
///
/// A profile that is not the active one is stored inside `profiles` and never
/// passes through that setting's writer, so nothing else would clamp it - and
/// an out-of-range layout would change under the user the moment they switched
/// to it.
ToolbarLayout clampToolbarLayout(ToolbarLayout value) {
  final clamped = value.copyWith(
    columns: _clampInt(value.columns, kToolbarMinColumns, kToolbarMaxColumns),
    rows: _clampInt(value.rows, kToolbarMinRows, kToolbarMaxRows),
    pages: _clampInt(value.pages, kToolbarMinPages, kToolbarMaxPages),
    buttonHeight: value.buttonHeight
        .clamp(kToolbarMinButtonHeight, kToolbarMaxButtonHeight)
        .toDouble(),
  );
  return clamped.copyWith(
    order: normalizeToolbarOrder(clamped.order, slotCount: clamped.slotCount),
  );
}

/// The layout profile [id] holds, falling back to the active one when [id]
/// names nothing - a profile can be deleted from under an open editor.
ToolbarLayout toolbarProfileLayout(String id) {
  final profiles = toolbarSettings.profiles.value;
  final index = profiles.profiles.indexWhere((profile) => profile.id == id);
  return index < 0 ? profiles.active.layout : profiles.profiles[index].layout;
}

/// Writes [layout] into profile [id], and into the live toolbar as well when
/// that profile is the one in use.
///
/// This is what lets the editor open a layout without handing the toolbar to
/// it: [saveToolbarLayout] can only ever write to the active profile, so it
/// would have put the changes in the wrong one.
Future<void> saveToolbarProfileLayout(String id, ToolbarLayout layout) async {
  final profiles = toolbarSettings.profiles.value;
  if (id == profiles.activeId) {
    await saveToolbarLayout(layout);
    return;
  }
  final index = profiles.profiles.indexWhere((profile) => profile.id == id);
  if (index < 0) return;
  await saveToolbarProfiles(
    profiles.withProfile(
      profiles.profiles[index].copyWith(layout: clampToolbarLayout(layout)),
    ),
  );
}

/// Switches the toolbar to [id] - which is what makes that profile's grid the
/// one every session draws.
Future<void> activateToolbarProfile(String id) async {
  final next = toolbarSettings.profiles.value.activated(id);
  await toolbarSettings.profiles.set(next);
  await saveToolbarLayout(next.active.layout);
}
