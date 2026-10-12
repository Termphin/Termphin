import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/completion/command_completion.dart';
import 'package:termphin/services/completion/remote_completion.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

HostCompletionData _host({
  List<String> history = const [],
  Set<String> commands = const {},
}) => HostCompletionData(
  history: history,
  commands: commands,
  engine: CompletionEngine.bash,
);

List<String> _labels(List<CommandSuggestion> s) => [for (final x in s) x.label];

void main() {
  group('parseProbe', () {
    test('reads each shell history format and the commands on PATH', () {
      final data = parseProbe(
        _bytes(
          '@@termphin:shell zsh\n'
          '@@termphin:has bash\n'
          '@@termphin:bashcomp /usr/share/bash-completion/bash_completion\n'
          '@@termphin:history .bash_history\n'
          '#1700000000\n'
          'ls -la\n'
          '\n'
          '@@termphin:history .zsh_history\n'
          ': 1700000001:0;git status\n'
          '@@termphin:history fish_history\n'
          '- cmd: htop\n'
          '  when: 1700000002\n'
          '@@termphin:commands\n'
          'git\n'
          'htop\n',
        ),
      );

      expect(data.history, ['ls -la', 'htop', 'git status']);
      expect(data.commands, {'git', 'htop'});
      expect(data.engine, CompletionEngine.bash);
      expect(
        data.bashCompletionPath,
        '/usr/share/bash-completion/bash_completion',
      );
    });

    test('reads Windows output: CRLF, and progress noise on stderr', () {
      final data = parseProbe(
        _bytes(
          '#< CLIXML\r\n'
          '@@termphin:shell powershell\r\n'
          '@@termphin:history ConsoleHost_history.txt\r\n'
          'Get-Date\r\n'
          '@@termphin:commands\r\n'
          'Get-ChildItem\r\n'
          'notepad\r\n'
          '<Objs Version="1.1.0.1"><Obj S="progress"/></Objs>',
        ),
      );

      expect(data.engine, CompletionEngine.powershell);
      expect(data.history, ['Get-Date']);
      expect(data.commands, {'Get-ChildItem', 'notepad'});
      expect(parseCandidates(_bytes('#< CLIXML\r\n-Recurse\r\n<Objs />')), [
        '-Recurse',
      ]);
    });

    test('fish is the engine only where it is the login shell', () {
      const both = '@@termphin:has bash\n@@termphin:has fish\n';
      expect(
        parseProbe(_bytes('@@termphin:shell fish\n$both')).engine,
        CompletionEngine.fish,
      );
      expect(
        parseProbe(_bytes('@@termphin:shell bash\n$both')).engine,
        CompletionEngine.bash,
      );
      expect(parseProbe(_bytes('')).engine, CompletionEngine.none);
    });

    test('zsh history is unmetafied before decoding', () {
      final data = parseProbe(
        Uint8List.fromList([
          ...utf8.encode('@@termphin:history .zsh_history\n: 1:0;echo '),
          0x83,
          0xc5 ^ 0x20,
          0x83,
          0xbc ^ 0x20,
          0x0a,
        ]),
      );

      expect(data.history, ['echo ż']);
    });

    test('commands carrying a credential are dropped', () {
      final data = parseProbe(
        _bytes(
          '@@termphin:history .bash_history\n'
          'export API_KEY=abc\n'
          'mysql -u root -phunter2\n'
          ' hidden on purpose\n'
          'ls\n',
        ),
      );

      expect(data.history, ['ls']);
    });
  });

  test('a failed probe gives every host its own empty history', () {
    HostCompletionData.empty.remember('ls');

    expect(HostCompletionData.empty.history, isEmpty);
  });

  test('fish descriptions are dropped from candidates', () {
    expect(parseCandidates(_bytes('checkout\tSwitch branches\nclone\n')), [
      'checkout',
      'clone',
    ]);
  });

  test('the query stops at the directory part of the word being typed', () {
    expect(completionQuery('git ch'), 'git ');
    expect(completionQuery('ls lib/wid'), 'ls lib/');
    expect(completionQuery('gi'), 'ls ');
    expect(completionQuery('./te'), 'ls ./');
    expect(completionQuery('ls -l'), 'ls -');
    expect(completionQuery('git commit --am'), 'git commit --');
    expect(
      completionQuery(r'cd C:\Us', engine: CompletionEngine.powershell),
      r'cd C:\',
    );
  });

  test('history ranks the most recent command first', () {
    expect(rankHistory(['a', 'b', 'b', 'b', 'c']), ['c', 'b', 'a']);
  });

  group('suggest', () {
    test('nothing is offered on an empty line', () {
      final host = _host(commands: {'git'});

      expect(suggest('', host, ranked: ['make', 'ls']), isEmpty);
      expect(suggest('  ', host, ranked: ['make', 'ls']), isEmpty);
    });

    test('a space keeps history and offers what follows the word', () {
      final s = suggest(
        'git ',
        _host(commands: {'git'}),
        ranked: ['git status', 'ls'],
        words: ['checkout', 'commit'],
      );

      expect(_labels(s), ['git status', 'checkout', 'commit']);
    });

    test('whole lines from history come first, then words', () {
      final s = suggest(
        'git ch',
        _host(),
        ranked: ['git checkout main'],
        words: ['checkout', 'cherry-pick', 'clone'],
      );

      expect(_labels(s), ['git checkout main', 'checkout', 'cherry-pick']);
      expect(s.map((x) => x.insert), ['eckout main', 'eckout ', 'erry-pick ']);
    });

    test('the first word completes from history, then files, then PATH', () {
      final s = suggest(
        'ht',
        _host(commands: {'htpasswd', 'htop', 'http'}),
        ranked: ['htop -d 5'],
        words: ['html/', 'htrun.sh', 'README.md'],
      );

      expect(_labels(s), [
        'htop -d 5',
        'htop',
        './html/',
        './htrun.sh',
        'http',
        'htpasswd',
      ]);
    });

    test('a file in the current directory is offered as ./name', () {
      final s = suggest('te', _host(), words: ['test.sh', 'tests/']);

      expect(_labels(s), ['./test.sh', './tests/']);
      expect(s.first.erase, 2);
      expect(s.first.insert, './test.sh ');
      expect(s.last.insert, './tests/');
    });

    test('a word starting ./ is finished in place', () {
      final s = suggest('./te', _host(), words: ['./test.sh', './README.md']);

      expect(s.single.label, './test.sh');
      expect(s.single.insert, 'st.sh ');
      expect(s.single.erase, 0);
    });

    test('an option taking a value is completed without a space', () {
      final s = suggest('ls --co', _host(), words: ['--color=', '--context']);

      expect(s.map((x) => x.insert), ['lor=', 'ntext ']);
    });

    test('Windows matches regardless of case and takes backslashes', () {
      final data = HostCompletionData(
        history: const [],
        commands: const {'Get-ChildItem'},
        engine: CompletionEngine.powershell,
      );

      expect(suggest('get-ch', data).single.insert, 'ildItem ');
      expect(
        suggest(r'cd c:\us', data, words: [r'C:\Users\']).single.insert,
        r'ers\',
      );
    });

    test('a directory is completed without a trailing space', () {
      final s = suggest('cd lib/s', _host(), words: ['lib/screens/']);

      expect(s.single.label, 'lib/screens/');
      expect(s.single.insert, 'creens/');
    });
  });

  group('after a space', () {
    late List<String> asked;
    late Duration answerAfter;

    setUp(() {
      HostCompletionCache.clear();
      asked = [];
      answerAfter = Duration.zero;
    });

    /// The line a [completeCommand] asks about, read back out of the script.
    String queryOf(String command) {
      final outer = utf8.decode(
        base64.decode(RegExp(r'^echo (\S+) ').firstMatch(command)!.group(1)!),
      );
      final line = RegExp(
        r"TERMPHIN_LINE=\$\(printf %s '([^']*)'",
      ).firstMatch(outer)!.group(1)!;
      return utf8.decode(base64.decode(line));
    }

    CommandCompletion completion({
      List<String> history = const [],
      Map<String, String> answers = const {},
    }) => CommandCompletion(
      hostKey: 'host',
      windows: () => false,
      location: () => null,
      run: (command) async {
        if (command == probeCommand()) {
          return _bytes(
            '@@termphin:shell bash\n@@termphin:has bash\n'
            '@@termphin:history .bash_history\n${history.join('\n')}\n'
            '@@termphin:commands\ngit\ntee\n',
          );
        }
        asked.add(command);
        await Future<void>.delayed(answerAfter);
        return _bytes(answers[queryOf(command)] ?? 'checkout\ncherry\n');
      },
    );

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 300));

    test('nothing follows a word nothing matched', () async {
      final c = completion();
      c.update('foo');
      await settle();
      expect(c.suggestions.value, isEmpty);

      final before = asked.length;
      c.update('foo ');
      await settle();

      expect(c.suggestions.value, isEmpty);
      expect(asked.length, before, reason: 'no round trip for it either');
    });

    test('a command typed out in full still gets what follows it', () async {
      final c = completion();
      c.update('git');
      await settle();
      c.update('git ');
      await settle();

      expect(_labels(c.suggestions.value), ['checkout', 'cherry']);
    });

    test('typing on after the space brings suggestions back', () async {
      final c = completion();
      c.update('foo');
      await settle();
      c.update('foo ');
      await settle();
      c.update('foo c');
      await settle();

      expect(_labels(c.suggestions.value), ['checkout', 'cherry']);
    });

    test(
      'a space typed before the host answered is not held against it',
      () async {
        answerAfter = const Duration(milliseconds: 500);
        final c = completion();
        c.update('foo');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        c.update('foo ');
        await Future<void>.delayed(const Duration(milliseconds: 900));
        c.update('foo c');
        await settle();

        expect(_labels(c.suggestions.value), ['checkout', 'cherry']);
      },
    );
    test('a word left short of what was offered gets no paths', () async {
      final c = completion(answers: {'ls ': 'test.sh\nnotes.txt\n'});
      c.update('te');
      await settle();
      expect(_labels(c.suggestions.value), containsAll(['tee', './test.sh']));

      c.update('te ');
      await settle();

      expect(c.suggestions.value, isEmpty);
    });

    test('an option counts as known, so paths follow it', () async {
      final c = completion(answers: {'ls -': '--color\n', 'ls -l ': 'a.txt\n'});
      c.update('ls -l');
      await settle();
      c.update('ls -l ');
      await settle();
      c.update('ls -l a');
      await settle();

      expect(_labels(c.suggestions.value), ['a.txt']);
    });

    test('a directory typed without its slash counts as known', () async {
      final c = completion(answers: {'cd ': 'lib/\n', 'cd lib ': 'x/\n'});
      c.update('cd lib');
      await settle();
      c.update('cd lib ');
      await settle();
      c.update('cd lib x');
      await settle();

      expect(_labels(c.suggestions.value), ['x/']);
    });

    test(
      'history matching the line still shows after an unknown word',
      () async {
        final c = completion(
          history: ['git frob now'],
          answers: {'git ': 'checkout\n', 'git frob ': 'a.txt\n'},
        );
        c.update('git frob');
        await settle();
        c.update('git frob ');
        await settle();
        expect(_labels(c.suggestions.value), ['git frob now']);

        c.update('git frob n');
        await settle();
        expect(_labels(c.suggestions.value), ['git frob now']);
      },
    );
  });

  group('multi-line history', () {
    test('is dropped, so taking it never runs its first line', () {
      final data = parseProbe(
        _bytes(
          '@@termphin:shell zsh\n'
          '@@termphin:history .zsh_history\n'
          ': 1:0;for f in *; do\\\n'
          'echo \$f\\\n'
          'done\n'
          ': 2:0;ls\n'
          '@@termphin:history fish_history\n'
          r'- cmd: begin\n  date\nend'
          '\n'
          '- cmd: pwd\n',
        ),
      );

      expect(data.history, ['pwd', 'ls']);
    });

    test('is neither remembered nor suggested', () {
      final data = _host();
      data.remember('echo a\necho b');
      expect(data.history, isEmpty);

      expect(suggest('echo', _host(), ranked: ['echo a\nrm -rf x']), isEmpty);
    });
  });

  group('quoted words', () {
    test('a name with a blank is escaped when typed', () {
      final s = suggest('cat My', _host(), words: ['My Docs/', 'My (1).txt']);

      expect(s.map((x) => x.insert), [r'\ Docs/', r'\ \(1\).txt ']);
      expect(_labels(s), ['My Docs/', 'My (1).txt']);
    });

    test('an escaped word is matched by what it means', () {
      final s = suggest(r'cat My\ D', _host(), words: ['My Docs/']);

      expect(s.single.insert, 'ocs/');
      expect(completionQuery(r'cat My\ Docs/a'), r'cat My\ Docs/');
    });

    test('a quoted word is finished inside its quote and closed', () {
      final s = suggest("cat 'My D", _host(), words: ["My Doc's.txt"]);

      expect(s.single.insert, r"oc'\''s.txt' ");
    });
  });

  group('option values', () {
    test('bash answers for what follows the =, and it is matched so', () {
      final s = suggest('tar --file=sr', _host(), words: ['src/', 'x.tar']);

      expect(s.single.label, 'src/');
      expect(s.single.insert, 'c/');
      expect(completionQuery('tar --file=sr'), 'tar --file=');
      expect(completionQuery('scp host:/et'), 'scp host:/');
    });

    test('fish answers with the whole word', () {
      final data = HostCompletionData(
        history: const [],
        commands: const {},
        engine: CompletionEngine.fish,
      );

      expect(
        suggest('ls --color=al', data, words: ['--color=always']).single.insert,
        'ways ',
      );
    });
  });

  group('loose matches', () {
    test('a word in the wrong case is rewritten', () {
      final s = suggest('Git', _host(commands: {'git'}));

      expect(s.single.label, 'git');
      expect(s.single.erase, 3);
      expect(s.single.insert, 'git ');
    });

    test('a command one typo away is offered when nothing starts so', () {
      final s = suggest('gti', _host(commands: {'git', 'grep'}));

      expect(_labels(s), ['git']);
      expect(s.single.erase, 3);
    });

    test('a subcommand one typo away is offered too', () {
      final s = suggest('git chekc', _host(), words: ['checkout', 'clone']);

      expect(s.single.label, 'checkout');
      expect(s.single.erase, 5);
      expect(s.single.insert, 'checkout ');
    });

    test('no more than three typo rewrites are offered', () {
      const near = ['abd', 'abe', 'abf', 'abg', 'abh'];

      expect(suggest('cd abc', _host(), words: near), hasLength(3));
      expect(
        suggest('abc', _host(), ranked: [for (final n in near) '$n x']),
        hasLength(3),
      );
    });

    test('an exact match keeps the loose ones away', () {
      final s = suggest('gi', _host(commands: {'git', 'Gimp'}));

      expect(_labels(s), ['git']);
    });
  });

  test('history run in this directory ranks first', () {
    expect(rankHistory(['make test', 'make build'], here: ['make test']), [
      'make test',
      'make build',
    ]);
  });

  group('session', () {
    late List<String> asked;
    late String directory;

    setUp(() {
      HostCompletionCache.clear();
      HostCompletionCache.now = DateTime.now;
      asked = [];
      directory = '/a';
    });

    tearDown(() => HostCompletionCache.now = DateTime.now);

    var probes = 0;
    CommandCompletion completion({bool failProbe = false}) => CommandCompletion(
      hostKey: 'host',
      windows: () => false,
      location: () => '.cache/cwd',
      run: (command) async {
        if (command == probeCommand()) {
          probes++;
          if (failProbe) throw StateError('down');
          return _bytes(
            '@@termphin:shell bash\n@@termphin:has bash\n'
            '@@termphin:commands\ngit\nmake\n',
          );
        }
        asked.add(command);
        return _bytes('@@termphin:cwd $directory\ntest\nbuild\n');
      },
    );

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 300));

    test('a command ranks first where it was run', () async {
      final c = completion();
      c.update('make t');
      await settle();
      c.remember('make test');
      await settle();

      directory = '/b';
      c.update('');
      c.update('make b');
      await settle();
      c.update('make bu');
      await settle();
      c.remember('make build');
      await settle();

      directory = '/a';
      c.update('');
      c.update('ma');
      await settle();
      c.update('mak');
      await settle();

      expect(_labels(c.suggestions.value).first, 'make test');
    });

    test('an answer is kept for the line, not asked again', () async {
      final c = completion();
      c.update('cd src/a');
      await settle();
      c.update('cd lib/b');
      await settle();
      final before = asked.length;
      c.update('cd src/ab');
      await settle();

      expect(asked.length, before);
    });

    test('a finished word is asked about without the pause', () async {
      final c = completion();
      c.update('gi');
      await settle();
      final before = asked.length;
      c.update('git ');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(asked.length, before + 1);
    });

    test(
      'host data is read again once stale, keeping what was typed',
      () async {
        probes = 0;
        var now = DateTime(2026);
        HostCompletionCache.now = () => now;
        final c = completion();
        c.update('ma');
        await settle();
        c.remember('make deploy');
        await settle();
        expect(probes, 1);

        now = now.add(HostCompletionCache.freshFor);
        c.update('mak');
        await settle();
        c.update('make d');
        await settle();

        expect(probes, 2);
        expect(_labels(c.suggestions.value), contains('make deploy'));
      },
    );

    test('a failed probe is retried after a minute, not at once', () async {
      probes = 0;
      var now = DateTime(2026);
      HostCompletionCache.now = () => now;
      final c = completion(failProbe: true);
      c.update('ma');
      await settle();
      c.update('mak');
      await settle();
      expect(probes, 1);

      now = now.add(HostCompletionCache.retryAfter);
      c.update('make');
      await settle();
      expect(probes, 2);
    });
  });
}
