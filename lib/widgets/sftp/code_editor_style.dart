import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart' as re;

import '../../services/settings/editor_settings.dart';
import '../../services/settings/terminal_settings.dart';
import '../../theme/theme.dart';

/// Syntax colours made from a terminal scheme's own ANSI palette, so a file
/// reads in the same colours as the shell around it: Dracula's strings are
/// Dracula's green. The same token classes Atom One colours, mapped to the
/// ANSI roles Atom's hues stand for. The light schemes' ANSI colours are
/// already tuned to read on their backgrounds, which a fixed palette was not.
Map<String, TextStyle> schemeHighlightPalette(TerminalColorScheme s) {
  TextStyle c(Color color) => TextStyle(color: color);
  final dim = TextStyle(color: s.brightBlack, fontStyle: FontStyle.italic);
  return {
    'root': TextStyle(color: s.foreground),
    'comment': dim,
    'quote': dim,
    for (final k in ['doctag', 'keyword', 'formula']) k: c(s.magenta),
    for (final k in ['section', 'name', 'selector-tag', 'deletion', 'subst'])
      k: c(s.red),
    'literal': c(s.cyan),
    for (final k in [
      'string',
      'regexp',
      'addition',
      'attribute',
      'meta-string',
    ])
      k: c(s.green),
    for (final k in [
      'attr',
      'variable',
      'template-variable',
      'type',
      'selector-class',
      'selector-attr',
      'selector-pseudo',
      'number',
    ])
      k: c(s.yellow),
    for (final k in [
      'symbol',
      'bullet',
      'link',
      'meta',
      'selector-id',
      'title',
    ])
      k: c(s.blue),
    for (final k in ['built_in', 'title.class_', 'class-title'])
      k: c(s.brightYellow),
    'emphasis': const TextStyle(fontStyle: FontStyle.italic),
    'strong': const TextStyle(fontWeight: FontWeight.bold),
  };
}

/// The palette for the scheme the terminal is set to - the same scheme the
/// editor's background comes from, through [TerminalSchemeTheme].
Map<String, TextStyle> editorHighlightPalette() => schemeHighlightPalette(
  AppTheme.terminalSchemeForId(terminalSettings.scheme.value),
);

/// One style for every place a file is drawn - the editor and the settings
/// preview - so the preview is the editor rather than a picture of it.
re.CodeEditorStyle codeEditorStyle(
  BuildContext context, {
  required double fontSize,
  ({String id, re.CodeHighlightThemeMode mode})? language,
}) {
  final colors = context.colors;
  return re.CodeEditorStyle(
    fontSize: fontSize,
    fontFamily: editorSettings.fontFamily.value,
    fontFamilyFallback: const ['monospace'],
    fontHeight: editorSettings.lineHeight.value,
    textColor: colors.textPrimary,
    backgroundColor: colors.backgroundPrimary,
    selectionColor: colors.primary.withValues(alpha: 0.3),
    highlightColor: colors.primary.withValues(alpha: 0.18),
    cursorColor: colors.primary,
    chunkIndicatorColor: colors.textTertiary,
    codeTheme: language == null
        ? null
        : re.CodeHighlightTheme(
            languages: {language.id: language.mode},
            theme: editorHighlightPalette(),
          ),
  );
}

/// Line numbers when the setting asks for them, nothing otherwise.
re.CodeIndicatorBuilder? editorLineNumbers() {
  if (!editorSettings.lineNumbers.value) return null;
  return (context, editingController, chunkController, notifier) => Padding(
    padding: const EdgeInsets.only(right: AppTheme.space12),
    child: re.DefaultCodeLineNumber(
      controller: editingController,
      notifier: notifier,
    ),
  );
}
