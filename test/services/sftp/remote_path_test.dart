import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/sftp/remote_path.dart';
import 'package:termphin/utils/sftp_path.dart';

void main() {
  group('remotePathSegments', () {
    test('POSIX', () {
      expect(remotePathSegments('/a/b/c'), ['a', 'b', 'c']);
      expect(remotePathSegments('/'), <String>[]);
      expect(remotePathSegments('/a/b/'), ['a', 'b']);
    });

    test('Windows carries the drive letter as the first segment', () {
      expect(remotePathSegments('/C:/Users/me'), ['C:', 'Users', 'me']);
      expect(remotePathSegments('/C:/'), ['C:']);
    });
  });

  group('joinRemotePath', () {
    test('POSIX', () {
      expect(joinRemotePath('/a/b', 'c.txt'), '/a/b/c.txt');
      expect(joinRemotePath('/', 'c.txt'), '/c.txt');
    });

    test('Windows', () {
      expect(joinRemotePath('/C:/Users', 'file.txt'), '/C:/Users/file.txt');
      expect(joinRemotePath('/C:/', 'file.txt'), '/C:/file.txt');
    });
  });

  group('remoteSegmentPath', () {
    test('POSIX', () {
      expect(remoteSegmentPath('/a/b/c', 0), '/a');
      expect(remoteSegmentPath('/a/b/c', 1), '/a/b');
      expect(remoteSegmentPath('/a/b/c', 2), '/a/b/c');
    });

    test('Windows stays on the drive for the first segment', () {
      expect(remoteSegmentPath('/C:/Users/me', 0), '/C:/');
      expect(remoteSegmentPath('/C:/Users/me', 1), '/C:/Users');
      expect(remoteSegmentPath('/C:/Users/me', 2), '/C:/Users/me');
    });
  });

  group('remoteRootPath', () {
    test('POSIX', () {
      expect(remoteRootPath('/a/b/c'), '/');
      expect(remoteRootPath('/'), '/');
    });

    test('Windows stops at the drive root', () {
      expect(remoteRootPath('/C:/Users/me'), '/C:/');
      expect(remoteRootPath('/C:/'), '/C:/');
    });
  });

  group('sftpParentPath (reused by _goUp)', () {
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
