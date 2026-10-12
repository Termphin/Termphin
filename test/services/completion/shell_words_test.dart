import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/completion/shell_words.dart';

void main() {
  group('readLastWord', () {
    test('an escaped or quoted blank does not end the word', () {
      final escaped = readLastWord(r'cat My\ Do');
      expect(escaped.before, 'cat ');
      expect(escaped.raw, r'My\ Do');
      expect(escaped.plain, 'My Do');
      expect(escaped.quote, isNull);

      final quoted = readLastWord("cat 'My Do");
      expect(quoted.raw, "'My Do");
      expect(quoted.plain, 'My Do');
      expect(quoted.quote, "'");

      final double = readLastWord(r'cat "a\$b\c');
      expect(double.plain, r'a$b\c');
      expect(double.quote, '"');
    });

    test('a break cuts the word after the command, not the command', () {
      final option = readLastWord('tar --file=sr', breaks: '=:');
      expect(option.plainTail, 'sr');
      expect(option.rawTail, 'sr');

      expect(readLastWord('A=b', breaks: '=:').plainTail, 'A=b');
      expect(readLastWord(r'cp a\:b', breaks: '=:').plainTail, 'a:b');
    });

    test('PowerShell lines are cut at the last blank only', () {
      final word = readLastWord(r"cd 'C:\Program", posix: false);
      expect(word.before, 'cd ');
      expect(word.plain, r"'C:\Program");
    });
  });

  test('completion words are cut the way bash cuts COMP_WORDS', () {
    expect(completionWords('tar --file=sr'), ['tar', '--file', '=', 'sr']);
    expect(completionWords(r'cat My\ Docs/'), ['cat', r'My\ Docs/']);
    expect(completionWords("cat 'a b' "), ['cat', "'a b'", '']);
    expect(completionWords('scp host:'), ['scp', 'host', ':']);
    expect(completionWords(''), ['']);
  });

  test('escaping follows the quote the word is in', () {
    expect(shellEscape("it's (1).txt"), r"it\'s\ \(1\).txt");
    expect(shellEscape("it's", quote: "'"), r"it'\''s");
    expect(shellEscape(r'a "$b"', quote: '"'), r'a \"\$b\"');
    expect(shellEscape('a=b:c~'), 'a=b:c~');
  });

  test('a near prefix is one edit away from how a name starts', () {
    expect(isNearPrefix('gti', 'git'), isTrue);
    expect(isNearPrefix('dokc', 'docker-compose'), isTrue);
    expect(isNearPrefix('sytemctl', 'systemctl'), isTrue);
    expect(isNearPrefix('gitt', 'git'), isTrue);
    expect(isNearPrefix('xyz', 'git'), isFalse);
    expect(isNearPrefix('sl', 'ls'), isFalse, reason: 'too short to guess');
  });
}
