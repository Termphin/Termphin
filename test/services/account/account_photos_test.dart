import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/account/account_photos.dart';

void main() {
  late Directory root;
  late List<Uri> fetched;
  late AccountPhotos photos;

  setUp(() {
    root = Directory.systemTemp.createTempSync('account_photos');
    fetched = [];
    photos = AccountPhotos(
      fetch: (url) async {
        fetched.add(url);
        return Uint8List.fromList(url.toString().codeUnits);
      },
      directory: () async => Directory('${root.path}/account'),
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('a picture is fetched once and read from the device after', () async {
    const url = 'https://avatars.githubusercontent.com/u/1?v=4';

    final first = await photos.fileFor(url);
    final second = await photos.fileFor(url);

    expect(fetched, hasLength(1));
    expect(second!.path, first!.path);
    expect(second.readAsStringSync(), url);
  });

  test('a new picture replaces the old one', () async {
    await photos.fileFor('https://example.com/a.png');
    final newer = await photos.fileFor('https://example.com/b.png');

    final kept = Directory('${root.path}/account').listSync();
    expect(kept.map((entry) => entry.path), [newer!.path]);
  });

  test('signing out deletes the kept picture', () async {
    await photos.fileFor('https://example.com/a.png');

    await photos.clear();

    expect(Directory('${root.path}/account').existsSync(), isFalse);
  });

  test('only https is fetched', () async {
    expect(await photos.fileFor('http://example.com/a.png'), isNull);
    expect(fetched, isEmpty);
  });
}
