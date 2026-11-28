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
}
