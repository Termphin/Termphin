import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/remote_shell.dart';
import 'package:termphin/services/sftp/upload_plan.dart';

void main() {
  group('sanitizedUploadName', () {
    test('collapses anything that would split into extra arguments', () {
      expect(
        sanitizedUploadName('my report (final).txt'),
        'my_report_final_.txt',
      );
    });

    test('keeps the tail of a very long name', () {
      final name = '${'a' * 200}.log';
      final result = sanitizedUploadName(name);
      expect(result.length, 120);
      expect(result.endsWith('.log'), isTrue);
    });
  });

  group('planUploadPaths', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

    test('drops files straight into the directory when not timestamped', () {
      expect(
        planUploadPaths(
          fileNames: ['a.txt', 'b.txt'],
          directory: '/home/tester',
          timestamped: false,
        ),
        ['/home/tester/a.txt', '/home/tester/b.txt'],
      );
    });

    test('timestamps for the scratch directory', () {
      expect(
        planUploadPaths(
          fileNames: ['a.txt'],
          directory: '/tmp',
          timestamped: true,
          now: now,
        ),
        ['/tmp/1700000000000_a.txt'],
      );
    });

    test('tolerates a trailing slash on the directory', () {
      expect(
        planUploadPaths(
          fileNames: ['a.txt'],
          directory: '/tmp/',
          timestamped: false,
        ),
        ['/tmp/a.txt'],
      );
    });

    test('two picked files never resolve to the same remote path', () {
      final paths = planUploadPaths(
        fileNames: ['notes.txt', 'notes.txt', 'notes.txt'],
        directory: '/tmp',
        timestamped: true,
        now: now,
      );
      expect(paths.toSet().length, 3);
      expect(paths, [
        '/tmp/1700000000000_notes.txt',
        '/tmp/1700000000000_notes-2.txt',
        '/tmp/1700000000000_notes-3.txt',
      ]);
    });

    test('uniquing keeps the extension where the name has one', () {
      final paths = planUploadPaths(
        fileNames: ['archive.tar.gz', 'archive.tar.gz'],
        directory: '/tmp',
        timestamped: false,
      );
      expect(paths.last, '/tmp/archive.tar-2.gz');
    });

    test('names that only differ by punctuation still get separate paths', () {
      final paths = planUploadPaths(
        fileNames: ['my file.txt', 'my+file.txt'],
        directory: '/tmp',
        timestamped: false,
      );
      expect(paths.toSet().length, 2);
    });
  });

  group('uploadPasteText', () {
    test('quotes a unix path so a space cannot split it', () {
      expect(
        uploadPasteText(['/tmp/my file.txt'], RemoteShellType.unix),
        r"'/tmp/my file.txt'",
      );
    });

    test('quotes for powershell on a windows session', () {
      expect(
        uploadPasteText([
          r'C:\Users\Jan Kowalski\a.txt',
        ], RemoteShellType.powershell),
        r'"C:\Users\Jan Kowalski\a.txt"',
      );
    });

    test('separates a batch with spaces so it reads as one argument list', () {
      expect(
        uploadPasteText(['/tmp/a.c', '/tmp/b.c'], RemoteShellType.unix),
        "'/tmp/a.c' '/tmp/b.c'",
      );
    });

    test('escapes a quote inside the path rather than ending the string', () {
      expect(
        uploadPasteText(["/tmp/it's.txt"], RemoteShellType.unix),
        r"'/tmp/it'\''s.txt'",
      );
    });
  });
}
