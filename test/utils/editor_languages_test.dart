import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/utils/editor_languages.dart';

void main() {
  test('common extensions map to a language id', () {
    final dart = editorLanguageForExtension('dart');
    expect(dart, isNotNull);
    expect(dart!.id, 'dart');

    expect(editorLanguageForExtension('py')!.id, 'python');
    expect(editorLanguageForExtension('rs')!.id, 'rust');
    expect(editorLanguageForExtension('ts')!.id, 'typescript');
    expect(editorLanguageForExtension('go')!.id, 'go');
  });

  test('aliases collapse to their parent language', () {
    expect(editorLanguageForExtension('yml')!.id, 'yaml');
    expect(editorLanguageForExtension('jsx')!.id, 'javascript');
    expect(editorLanguageForExtension('tsx')!.id, 'typescript');
    expect(editorLanguageForExtension('svg')!.id, 'xml');
    expect(editorLanguageForExtension('htm')!.id, 'xml');
    expect(editorLanguageForExtension('zsh')!.id, 'bash');
    expect(editorLanguageForExtension('toml')!.id, 'ini');
    expect(editorLanguageForExtension('patch')!.id, 'diff');
  });

  test('case-insensitive lookup', () {
    expect(editorLanguageForExtension('DART')!.id, 'dart');
    expect(editorLanguageForExtension('Py')!.id, 'python');
  });

  test('unknown extensions return null', () {
    expect(editorLanguageForExtension(''), isNull);
    expect(editorLanguageForExtension('xyzzy'), isNull);
    expect(editorLanguageForExtension('bin'), isNull);
  });

  test('every entry carries a highlight mode', () {
    for (final ext in [
      'dart',
      'json',
      'yaml',
      'xml',
      'md',
      'js',
      'ts',
      'py',
      'java',
      'kt',
      'c',
      'cpp',
      'cs',
      'go',
      'rs',
      'rb',
      'php',
      'sh',
      'sql',
      'css',
      'swift',
      'ini',
      'lua',
      'mk',
      'dockerfile',
      'ps1',
      'm',
      'diff',
    ]) {
      final entry = editorLanguageForExtension(ext);
      expect(entry, isNotNull, reason: ext);
      expect(entry!.mode.mode, isNotNull, reason: ext);
    }
  });
}
