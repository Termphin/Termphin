import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/app/font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every licence file shipped with the fonts is registered', () {
    final shipped = Directory('assets/fonts')
        .listSync()
        .map((entry) => entry.path)
        .where((path) => path.endsWith('.txt'))
        .toSet();

    expect(kFontLicenses.keys.toSet(), shipped);
  });

  test('the licences screen lists the fonts with their text', () async {
    registerFontLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    final fonts = entries.where(
      (entry) => entry.packages.contains('JetBrains Mono'),
    );

    expect(fonts, isNotEmpty);
    expect(
      fonts.first.paragraphs.map((paragraph) => paragraph.text).join(' '),
      contains('SIL OPEN FONT LICENSE'),
    );
  });
}
