import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/sftp/sftp_remote_ops.dart';
import 'package:termphin/utils/sftp_path.dart';

/// The script inside a `powershell -EncodedCommand` line.
String _decodePowerShell(String commandLine) {
  final encoded = commandLine.split(' ').last;
  final bytes = base64.decode(encoded);
  final units = [
    for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
  ];
  return String.fromCharCodes(units);
}

void main() {
  group('POSIX commands, run by a real sh', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('ops'));
    tearDown(() => root.deleteSync(recursive: true));

    Future<ProcessResult> run(String command) =>
        Process.run('sh', ['-c', command], workingDirectory: root.path);

    const nasty = [
      "it's here",
      r'$(touch pwned)',
      '-rf',
      'back\\slash',
      'semi;colon & "quote"',
      'new\nline',
      'zażółć 日本',
      '*glob?[x]',
    ];

    for (final name in nasty) {
      test(
        'copies a folder named ${jsonEncode(name)} with its contents',
        () async {
          final source = Directory('${root.path}/$name')..createSync();
          File('${source.path}/inner.txt').writeAsStringSync('data');
          final target = '${root.path}/copy of $name';

          final result = await run(copyCommand(source.path, target));

          expect(result.exitCode, 0, reason: '${result.stderr}');
          expect(File('$target/inner.txt').readAsStringSync(), 'data');
          expect(source.existsSync(), isTrue);
          expect(File('${root.path}/pwned').existsSync(), isFalse);
        },
      );

      test('moves a file named ${jsonEncode(name)}', () async {
        final source = File('${root.path}/$name')..writeAsStringSync('x');
        final target = '${root.path}/moved $name';

        final result = await run(moveCommand(source.path, target));

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(File(target).readAsStringSync(), 'x');
        expect(source.existsSync(), isFalse);
      });
    }

    test('keeps mode and modification time', () async {
      final source = File('${root.path}/script.sh')..writeAsStringSync('x');
      await Process.run('chmod', ['750', source.path]);
      final past = DateTime(2020, 1, 2, 3, 4, 5);
      source.setLastModifiedSync(past);
      final target = '${root.path}/copy.sh';

      final result = await run(copyCommand(source.path, target));

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File(target).statSync().mode & 0x1ff, 0x1e8);
      expect(File(target).lastModifiedSync(), past);
    });

    test('a symlink picked itself is copied as a link', () async {
      final real = Directory('${root.path}/real')..createSync();
      final link = Link('${root.path}/shortcut')..createSync(real.path);

      final result = await run(copyCommand(link.path, '${root.path}/copy'));

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(FileSystemEntity.isLinkSync('${root.path}/copy'), isTrue);
    });

    test('moves a folder with its contents', () async {
      final source = Directory('${root.path}/folder')..createSync();
      File('${source.path}/inner.txt').writeAsStringSync('data');

      final result = await run(moveCommand(source.path, '${root.path}/moved'));

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('${root.path}/moved/inner.txt').readAsStringSync(), 'data');
      expect(source.existsSync(), isFalse);
    });

    test('a target starting with a dash is a name, not an option', () async {
      final source = File('${root.path}/a.txt')..writeAsStringSync('x');

      final result = await run(copyCommand(source.path, '-n'));

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('${root.path}/-n').existsSync(), isTrue);
    });

    test('copies a symlink as a link, not what it points at', () async {
      final big = Directory('${root.path}/big')..createSync();
      File('${big.path}/f').writeAsStringSync('f');
      final folder = Directory('${root.path}/folder')..createSync();
      Link('${folder.path}/link').createSync(big.path);

      final result = await run(copyCommand(folder.path, '${root.path}/copy'));

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(FileSystemEntity.isLinkSync('${root.path}/copy/link'), isTrue);
    });

    test('a refused copy exits non-zero and says why on stderr', () async {
      final result = await run(
        copyCommand('${root.path}/missing', '${root.path}/copy'),
      );

      expect(result.exitCode, isNot(0));
      expect('${result.stderr}', isNotEmpty);
    });

    test('the probe prints its marker', () async {
      final result = await run(execProbeCommand('/home/user'));
      expect('${result.stdout}', contains(execProbeMarker));
    });
  }, skip: Platform.isWindows);

  group('Windows commands', () {
    test('go to PowerShell with native paths and doubled quotes', () {
      final script = _decodePowerShell(
        copyCommand("/C:/Users/me/it's", '/C:/Users/me/dest'),
      );

      expect(
        script,
        contains(
          r"Copy-Item -LiteralPath 'C:\Users\me\it''s' "
          r"-Destination 'C:\Users\me\dest' -Recurse",
        ),
      );
      expect(script, contains('[Console]::Error.WriteLine'));
      expect(script, contains('exit 1'));
    });

    test('move uses Move-Item', () {
      final script = _decodePowerShell(moveCommand('/D:/a', '/D:/b'));
      expect(
        script,
        contains(r"Move-Item -LiteralPath 'D:\a' -Destination 'D:\b'"),
      );
    });

    test('the probe is chosen by the path it is asked about', () {
      expect(execProbeCommand('/C:/Users'), startsWith('powershell '));
      expect(execProbeCommand('/home/user'), startsWith('/bin/sh -c '));
    });
  });

  group('nextFreeName', () {
    test('numbers before the extension', () {
      expect(
        nextFreeName('report.pdf', {'report.pdf'}, isDirectory: false),
        'report (1).pdf',
      );
    });

    test('skips numbers already taken', () {
      expect(
        nextFreeName('report.pdf', {
          'report.pdf',
          'report (1).pdf',
          'report (2).pdf',
        }, isDirectory: false),
        'report (3).pdf',
      );
    });

    test('a copy of a copy counts on instead of stacking', () {
      expect(
        nextFreeName('report (1).pdf', {
          'report.pdf',
          'report (1).pdf',
        }, isDirectory: false),
        'report (2).pdf',
      );
    });

    test('keeps .tar.gz together', () {
      expect(
        nextFreeName('backup.tar.gz', {}, isDirectory: false),
        'backup (1).tar.gz',
      );
    });

    test('a dotfile has no extension to keep', () {
      expect(nextFreeName('.bashrc', {}, isDirectory: false), '.bashrc (1)');
    });

    test('a folder name is never split at a dot', () {
      expect(nextFreeName('v1.2', {}, isDirectory: true), 'v1.2 (1)');
    });
  });

  group('isSameOrInside', () {
    test('a sibling with a common prefix is not inside', () {
      expect(isSameOrInside('/srv/app-old', '/srv/app'), isFalse);
      expect(isSameOrInside('/srv/app/sub', '/srv/app'), isTrue);
      expect(isSameOrInside('/srv/app/', '/srv/app'), isTrue);
    });

    test('everything is inside the root', () {
      expect(isSameOrInside('/etc', '/'), isTrue);
    });

    test('Windows paths compare without case', () {
      expect(isSameOrInside('/c:/users/ME/x', '/C:/Users/me'), isTrue);
    });
  });

  group('canTransferInto', () {
    test('a folder cannot go into itself or below itself', () {
      bool into(String destination) => canTransferInto(
        destination: destination,
        sourceDirectory: '/home',
        sources: ['/home/app'],
        move: false,
      );

      expect(into('/home/app'), isFalse);
      expect(into('/home/app/src'), isFalse);
      expect(into('/home/app-old'), isTrue);
    });

    test('a move into its own folder changes nothing; a copy duplicates', () {
      bool into({required bool move}) => canTransferInto(
        destination: '/home/',
        sourceDirectory: '/home',
        sources: ['/home/a.txt'],
        move: move,
      );

      expect(into(move: true), isFalse);
      expect(into(move: false), isTrue);
    });
  });

  group('planTransfers', () {
    const entries = [
      RemoteEntry('a.txt', isDirectory: false),
      RemoteEntry('b.txt', isDirectory: false),
    ];

    TransferPlan plan(ConflictChoice choice, {Set<String>? existing}) =>
        planTransfers(
          sourceDirectory: '/src',
          entries: entries,
          destination: '/dst',
          existing: existing ?? {'a.txt'},
          choice: choice,
        );

    test('skip leaves a clash alone and counts it', () {
      final result = plan(ConflictChoice.skip);
      expect(result.transfers.map((t) => t.to), ['/dst/b.txt']);
      expect(result.skipped, 1);
    });

    test('replace marks only the clash for clearing', () {
      final result = plan(ConflictChoice.replace);
      expect(result.transfers.map((t) => (t.to, t.replaceExisting)), [
        ('/dst/a.txt', true),
        ('/dst/b.txt', false),
      ]);
    });

    test('keep both renames only the clash', () {
      final result = plan(ConflictChoice.keepBoth);
      expect(result.transfers.map((t) => t.to), [
        '/dst/a (1).txt',
        '/dst/b.txt',
      ]);
    });

    test('keep both into the same folder gives every copy its own name', () {
      final result = planTransfers(
        sourceDirectory: '/src',
        entries: const [
          RemoteEntry('a.txt', isDirectory: false),
          RemoteEntry('a (1).txt', isDirectory: false),
        ],
        destination: '/src',
        existing: {'a.txt', 'a (1).txt'},
        choice: ConflictChoice.keepBoth,
      );
      final targets = result.transfers.map((t) => t.to).toList();
      expect(targets, ['/src/a (2).txt', '/src/a (3).txt']);
    });

    test('never clears a folder the source sits inside', () {
      final result = planTransfers(
        sourceDirectory: '/dst/app',
        entries: const [RemoteEntry('app', isDirectory: true)],
        destination: '/dst',
        existing: {'app'},
        choice: ConflictChoice.replace,
      );
      expect(result.transfers, isEmpty);
      expect(result.skipped, 1);
    });
  });

  group('on a Windows server names clash regardless of case', () {
    const entries = [RemoteEntry('A.txt', isDirectory: false)];

    test('the clash is found', () {
      expect(transferConflicts(entries, {'a.txt'}, destination: '/C:/dst'), [
        'A.txt',
      ]);
      expect(
        transferConflicts(entries, {'a.txt'}, destination: '/home/dst'),
        isEmpty,
        reason: 'a POSIX filesystem tells them apart',
      );
    });

    test('keep both picks a name free in any case', () {
      final plan = planTransfers(
        sourceDirectory: '/C:/src',
        entries: entries,
        destination: '/C:/dst',
        existing: {'a.txt', 'a (1).TXT'},
        choice: ConflictChoice.keepBoth,
      );
      expect(plan.transfers.single.to, '/C:/dst/A (2).txt');
    });

    test('replace clears what is there', () {
      final plan = planTransfers(
        sourceDirectory: '/C:/src',
        entries: entries,
        destination: '/C:/dst',
        existing: {'a.txt'},
        choice: ConflictChoice.replace,
      );
      expect(plan.transfers.single.replaceExisting, isTrue);
    });
  });

  group('sftpParentPath', () {
    test('POSIX', () {
      expect(sftpParentPath('/a/b'), '/a');
      expect(sftpParentPath('/a'), '/');
      expect(sftpParentPath('/'), '/');
    });

    test('Windows stops at the drive root', () {
      expect(sftpParentPath('/C:/Users/me'), '/C:/Users');
      expect(sftpParentPath('/C:/Users'), '/C:/');
      expect(sftpParentPath('/C:/'), '/C:/');
    });
  });
}
