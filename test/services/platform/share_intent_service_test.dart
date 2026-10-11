import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/platform/share_intent_service.dart';

void main() {
  Future<Uint8List?> neverRead(String id) => fail('read $id');
  Future<void> noRewind(String id) async {}

  SharedContent? parse(
    Map<Object?, Object?>? raw, {
    Future<Uint8List?> Function(String id)? read,
    Future<void> Function(String id)? rewind,
  }) => SharedContent.fromChannel(
    raw,
    read: read ?? neverRead,
    rewind: rewind ?? noRewind,
  );

  group('SharedContent.fromChannel', () {
    test('nothing shared is no share', () {
      expect(parse(null), isNull);
      expect(parse({}), isNull);
    });

    test('text alone is a share with no files that says it had text', () {
      final content = parse({'files': <Object?>[], 'text': true})!;
      expect(content.files, isEmpty);
      expect(content.hadText, isTrue);
    });

    test('files keep their names and sizes', () async {
      final content = parse({
        'files': [
          {'id': 'h1', 'name': 'a.pdf', 'size': 3},
          {'id': 'h2', 'name': 'b.jpg', 'size': null},
        ],
        'text': false,
      })!;
      expect(content.hadText, isFalse);
      expect([for (final f in content.files) f.name], ['a.pdf', 'b.jpg']);
      expect(await content.files[0].length(), 3);
      expect(await content.files[1].length(), isNull);
    });

    test('files none of which could be opened are still a share', () {
      final content = parse({'files': <Object?>[]});
      expect(content, isNotNull);
      expect(content!.files, isEmpty);
      expect(content.hadText, isFalse);
    });

    test('a file is read chunk by chunk until the native side runs out', () {
      final chunks = [
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3]),
      ];
      final content = parse({
        'files': [
          {'id': 'h1', 'name': 'a.bin', 'size': 3},
        ],
      }, read: (id) async => chunks.isEmpty ? null : chunks.removeAt(0))!;

      expect(
        content.files.single.open().expand((chunk) => chunk).toList(),
        completion([1, 2, 3]),
      );
    });

    test('every read starts from the beginning of the file', () async {
      final calls = <String>[];
      var left = 0;
      final content = parse(
        {
          'files': [
            {'id': 'h1', 'name': 'a.bin', 'size': 2},
          ],
        },
        read: (id) async {
          calls.add('read');
          if (left == 0) return null;
          left--;
          return Uint8List.fromList([7]);
        },
        rewind: (id) async {
          calls.add('rewind $id');
          left = 2;
        },
      )!;

      final file = content.files.single;
      await file.open().first;
      expect(await file.open().expand((c) => c).toList(), [7, 7]);
      expect(calls.where((c) => c.startsWith('rewind')), [
        'rewind h1',
        'rewind h1',
      ]);
    });

    test('a failed read surfaces as the local file failing', () {
      final content = parse({
        'files': [
          {'id': 'h1', 'name': 'a.bin', 'size': 3},
        ],
      }, read: (_) async => throw PlatformException(code: 'read'))!;

      expect(
        content.files.single.open().toList(),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
