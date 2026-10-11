import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:termphin/utils/file_icon.dart';
import 'package:termphin/utils/file_type.dart';
import 'package:termphin/utils/material_icons_map.dart';

void main() {
  group('fileTypeOf', () {
    test('files without an extension are text', () {
      expect(fileTypeOf('Makefile'), FileKind.text);
      expect(fileTypeOf('LICENSE'), FileKind.text);
    });

    test('dotfiles without a real extension are text', () {
      expect(fileTypeOf('.gitignore'), FileKind.text);
      expect(fileTypeOf('.bashrc'), FileKind.text);
    });

    test('dotfiles with an unknown extension are binary', () {
      expect(fileTypeOf('.env.secret'), FileKind.binary);
    });

    test('image extensions are recognized case-insensitively', () {
      expect(fileTypeOf('photo.JPG'), FileKind.image);
      expect(fileTypeOf('a.png'), FileKind.image);
      expect(fileTypeOf('a.webp'), FileKind.image);
      expect(fileTypeOf('a.heic'), FileKind.image);
      expect(fileTypeOf('a.ico'), FileKind.image);
    });

    test('code, config and markup extensions are text', () {
      for (final name in [
        'main.dart',
        'app.py',
        'index.js',
        'main.rs',
        'main.go',
        'config.json',
        'values.yaml',
        'setup.cfg',
        'index.html',
        'style.css',
        'run.sh',
        'dump.sql',
        'data.csv',
        'notes.txt',
        'app.log',
        'fix.patch',
      ]) {
        expect(fileTypeOf(name), FileKind.text, reason: name);
      }
    });

    test('unknown extensions are binary', () {
      expect(fileTypeOf('archive.zip'), FileKind.binary);
      expect(fileTypeOf('binary.exe'), FileKind.binary);
      expect(fileTypeOf('data.bin'), FileKind.binary);
    });

    test('only the last extension counts', () {
      expect(fileTypeOf('photo.tar.gz.png'), FileKind.image);
      expect(fileTypeOf('notes.png.txt'), FileKind.text);
    });
  });

  group('buildFileIcon', () {
    test('mapped extensions get a Material SVG asset icon', () {
      final widget = buildFileIcon('main.dart');

      expect(widget, isA<SvgPicture>());
      final svg = widget as SvgPicture;
      final bytes = svg.bytesLoader;
      expect(bytes, isNotNull);
    });

    test('full file names map before extensions', () {
      final widget = buildFileIcon('Dockerfile');

      expect(widget, isA<SvgPicture>());
    });

    test('unmapped text files fall back to the file-text glyph', () {
      final widget = buildFileIcon('script.lua');

      expect(widget, isA<Icon>());
      final icon = widget as Icon;
      expect(icon.icon, PhosphorIconsFill.fileText);
    });

    test('binary files fall back to the generic file glyph', () {
      final widget = buildFileIcon('data.bin');

      expect(widget, isA<Icon>());
      final icon = widget as Icon;
      expect(icon.icon, PhosphorIconsFill.file);
    });

    test('fallback color and size are applied', () {
      const color = Color(0xFF112233);
      final widget = buildFileIcon('data.bin', size: 42, fallbackColor: color);

      final icon = widget as Icon;
      expect(icon.size, 42);
      expect(icon.color, color);
    });
  });

  group('material icon assets', () {
    test('every mapped icon exists as an asset', () {
      final dir = Uri.file('assets/icons/material/');
      final names = {
        ...materialFileExtensions.values,
        ...materialFileNames.values,
      };

      final offenders = names
          .where((name) => !File.fromUri(dir.resolve('$name.svg')).existsSync())
          .toList();

      expect(offenders, isEmpty, reason: offenders.join(', '));
    });
  });
}
