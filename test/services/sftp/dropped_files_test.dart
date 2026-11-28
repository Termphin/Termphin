import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/sftp/dropped_files.dart';

void main() {
  test(
    'dropped files go up by name and content, a nameless one as dropped-N; folders are counted out',
    () async {
      final dir = await Directory.systemTemp.createTemp('dropped');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/report.txt')..writeAsStringSync('hello');

      final result = droppedUploads([
        DropItemFile(file.path),
        DropItemDirectory(dir.path, const []),
        DropItemFile.fromData(
          Uint8List.fromList(utf8.encode('from a browser')),
          name: 'dropped-2',
        ),
      ]);

      expect(result.folders, 1);
      expect(result.uploads.map((upload) => upload.name), [
        'report.txt',
        'dropped-2',
      ]);
      expect(
        utf8.decode(
          await result.uploads.first.open().expand((b) => b).toList(),
        ),
        'hello',
      );
      expect(await result.uploads.first.length(), 5);
      expect(
        utf8.decode(await result.uploads.last.open().expand((b) => b).toList()),
        'from a browser',
      );
    },
  );
}
