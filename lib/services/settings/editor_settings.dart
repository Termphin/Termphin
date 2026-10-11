import 'package:flutter/foundation.dart';

import 'setting.dart';
import 'terminal_settings.dart';

const double kEditorMinFontSize = 8;
const double kEditorMaxFontSize = 28;

/// How the SFTP text editor draws a file. Its own settings rather than the
/// terminal's: a file is read at a different size than a shell, and changing
/// one should not move the other.
class EditorSettings {
  EditorSettings._();

  static final EditorSettings instance = EditorSettings._();

  /// Written from the editor too - a pinch there is this same preference.
  final fontSize = Setting.number(
    'editor_font_size',
    fallback: 13,
    min: kEditorMinFontSize,
    max: kEditorMaxFontSize,
  );

  /// The terminal's fonts, so a file and a shell can be set in the same face.
  final fontFamily = Setting.text(
    'editor_font_family',
    fallback: 'HackNerdFontMono',
    allowed: kTerminalFontLabels.keys.toSet(),
  );

  final lineHeight = Setting.number(
    'editor_line_height',
    fallback: 1.5,
    min: 1.0,
    max: 2.2,
  );

  /// Spaces the Tab key and an indent insert. Read when a file opens -
  /// re_editor fixes it for the life of the buffer.
  final tabWidth = Setting.integer(
    'editor_tab_width',
    fallback: 2,
    min: 1,
    max: 8,
  );

  final lineNumbers = Setting.boolean('editor_line_numbers', fallback: true);

  /// The key predates this class; keeping it keeps everyone's choice.
  final wordWrap = Setting.boolean('editor_word_wrap', fallback: true);

  List<Setting<Object?>> get all => [
    fontSize,
    fontFamily,
    lineHeight,
    tabWidth,
    lineNumbers,
    wordWrap,
  ];

  late final Listenable changes = Listenable.merge(all);

  Future<void> load() async {
    await Future.wait([for (final setting in all) setting.load()]);
  }
}

final editorSettings = EditorSettings.instance;
