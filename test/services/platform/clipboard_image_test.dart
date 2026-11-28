import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/platform/clipboard_image.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('a pasted image is named by when it was pasted, to the second', () {
    expect(
      clipboardImageName(DateTime(2026, 11, 27, 8, 5, 9)),
      'clipboard-20261127-080509.png',
    );
  });

  test('a phone never reads an image off the clipboard', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await readClipboardImage(), isNull);
  });

  test('saveLocalClipboardImage writes bytes and avoids overwriting', () async {
    final dir = await Directory.systemTemp.createTemp('termphin-clip-test-');
    addTearDown(() => dir.delete(recursive: true));
    final when = DateTime(2026, 11, 28, 15, 10, 5);
    final png = Uint8List.fromList([137, 80, 78, 71]);

    final first = await saveLocalClipboardImage(png, directory: dir, now: when);
    final second = await saveLocalClipboardImage(
      png,
      directory: dir,
      now: when,
    );

    expect(first.path, endsWith('clipboard-20261128-151005.png'));
    expect(second.path, endsWith('clipboard-20261128-151005-2.png'));
    expect(await first.readAsBytes(), png);
    expect(await second.readAsBytes(), png);
  });
}
