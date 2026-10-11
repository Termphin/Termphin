import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/ssh/remote_agent_service.dart';
import 'package:termphin/utils/sftp_path.dart';

void main() {
  group('isWindowsSftpPath', () {
    test('recognises the form the SFTP server actually reports', () {
      expect(isWindowsSftpPath('/C:/Users/administrator'), isTrue);
      expect(isWindowsSftpPath('/D:/data'), isTrue);
      expect(isWindowsSftpPath('/c:/lower/case/drive'), isTrue);
    });

    test('leaves POSIX paths alone', () {
      expect(isWindowsSftpPath('/home/user'), isFalse);
      expect(isWindowsSftpPath('/'), isFalse);
      expect(isWindowsSftpPath('/usr/local/bin'), isFalse);
    });

    test('does not match a bare drive letter with no leading slash', () {
      expect(isWindowsSftpPath('C:/Users'), isFalse);
    });

    test('matches the drive root with no trailing slash', () {
      expect(isWindowsSftpPath('/C:'), isTrue);
    });

    test('does not match a directory that merely looks drive-like', () {
      expect(isWindowsSftpPath('/CC:/x'), isFalse);
      expect(isWindowsSftpPath('/1:/x'), isFalse);
    });
  });

  group('sftpPathToDisplay', () {
    test('turns a server path into the native Windows form', () {
      expect(
        sftpPathToDisplay('/C:/Users/administrator'),
        r'C:\Users\administrator',
      );
      expect(sftpPathToDisplay('/C:/'), r'C:\');
    });

    test('renders the drive root as an absolute path either way', () {
      expect(sftpPathToDisplay('/C:'), r'C:\');
    });

    test('keeps spaces and punctuation intact', () {
      expect(
        sftpPathToDisplay('/C:/Program Files (x86)/App'),
        r'C:\Program Files (x86)\App',
      );
    });

    test('passes POSIX paths through untouched', () {
      expect(sftpPathToDisplay('/home/user/notes.txt'), '/home/user/notes.txt');
      expect(sftpPathToDisplay('/'), '/');
    });
  });

  group('displayPathToSftp', () {
    test('converts the native form back to what the server expects', () {
      expect(
        displayPathToSftp(r'C:\Users\administrator'),
        '/C:/Users/administrator',
      );
      expect(displayPathToSftp(r'D:\data\file.txt'), '/D:/data/file.txt');
    });

    test('drops the trailing separator on a bare drive root', () {
      expect(displayPathToSftp(r'C:\'), '/C:');
    });

    test('passes POSIX paths through untouched', () {
      expect(displayPathToSftp('/home/user'), '/home/user');
    });

    test('round trips with sftpPathToDisplay', () {
      for (final path in [
        '/C:/Users/administrator',
        '/C:/Program Files/App',
        '/D:/x/y/z',
      ]) {
        expect(displayPathToSftp(sftpPathToDisplay(path)), path);
      }
    });
  });

  group('windowsQuote', () {
    test('wraps a path so spaces do not split it into arguments', () {
      expect(
        windowsQuote(r'C:\Program Files\termphin-agent.exe'),
        '"C:\\Program Files\\termphin-agent.exe"',
      );
    });

    test('doubles embedded quotes rather than letting them terminate', () {
      expect(windowsQuote('a"b'), '"a""b"');
    });

    test('always quotes, even when nothing needs escaping', () {
      expect(windowsQuote('plain'), '"plain"');
    });
  });

  group('shellQuote', () {
    test('single quotes and escapes embedded single quotes', () {
      expect(shellQuote('/home/user'), "'/home/user'");
      expect(shellQuote("it's"), r"'it'\''s'");
    });
  });
}
