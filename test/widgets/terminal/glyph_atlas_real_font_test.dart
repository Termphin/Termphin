import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:terminal_view/terminal_view.dart';

/// The glyph atlas against text laid out, in the font the app ships: the
/// package's own tests use the test font, whose every glyph is a box.
void main() {
  const family = 'HackNerdFontMono';

  const screen = [
    'drwxr-xr-x  5 user staff  160 Nov 13 19:21 \x1b[1;34mlib\x1b[0m',
    '\x1b[32m+  final terminal = SessionTerminal();\x1b[0m',
    '\x1b[31m-  final terminal = Terminal(maxLines: 10000);\x1b[0m',
    '\x1b[3mitalic\x1b[0m \x1b[1mbold\x1b[0m \x1b[1;3mboth\x1b[0m \x1b[2mfaint\x1b[0m',
    r'~!@#$%^&*()_+{}|:"<>?`-=[]\;,./ 0123456789 gjpqy',
    'The quick brown fox jumps over the lazy dog, twice over.',
  ];

  setUpAll(() async {
    final loader = FontLoader(family);
    for (final file in [
      'HackNerdFontMono-Regular.ttf',
      'HackNerdFontMono-Bold.ttf',
      'HackNerdFontMono-Italic.ttf',
      'HackNerdFontMono-BoldItalic.ttf',
    ]) {
      final font = File('assets/fonts/$file');
      if (!font.existsSync()) continue;
      loader.addFont(
        Future.value(ByteData.sublistView(font.readAsBytesSync())),
      );
    }
    await loader.load();
  });

  Future<ui.Image> render(
    WidgetTester tester, {
    required bool glyphAtlas,
    required double devicePixelRatio,
  }) async {
    tester.view
      ..devicePixelRatio = devicePixelRatio
      ..physicalSize = Size(420 * devicePixelRatio, 110 * devicePixelRatio);
    addTearDown(tester.view.reset);

    final terminal = Terminal()..write(screen.join('\r\n'));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundary,
          child: TerminalView(
            terminal,
            key: ValueKey(glyphAtlas),
            glyphAtlas: glyphAtlas,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            textStyle: const TerminalStyle(fontSize: 12, fontFamily: family),
          ),
        ),
      ),
    );
    await tester.pump();

    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(
      () => render.toImage(pixelRatio: devicePixelRatio),
    );
    await tester.pumpWidget(const SizedBox());
    return image!;
  }

  Future<Uint8List> rgba(WidgetTester tester, ui.Image image) async {
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return data!.buffer.asUint8List();
  }

  /// Saves [image] where `TERMPHIN_ATLAS_DUMP` points, for looking at.
  Future<void> dump(WidgetTester tester, ui.Image image, String name) async {
    final directory = Platform.environment['TERMPHIN_ATLAS_DUMP'];
    if (directory == null) return;
    final png = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    File('$directory/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  }

  /// How much light each rendering puts on the screen, and how far apart the
  /// two are pixel for pixel, both as a share of full white everywhere.
  ({double laidOut, double stamped, double apart}) compare(
    Uint8List laidOut,
    Uint8List stamped,
    Uint8List background,
  ) {
    var a = 0;
    var b = 0;
    var apart = 0;
    for (var at = 0; at < laidOut.length; at += 4) {
      for (var channel = 0; channel < 3; channel++) {
        final base = background[channel];
        a += (laidOut[at + channel] - base).abs();
        b += (stamped[at + channel] - base).abs();
        apart += (laidOut[at + channel] - stamped[at + channel]).abs();
      }
    }
    final full = laidOut.length / 4 * 3 * 255;
    return (laidOut: a / full, stamped: b / full, apart: apart / full);
  }

  for (final ratio in [3.0, 2.625, 2.0]) {
    testWidgets('stamped glyphs carry the same ink as laid out text at '
        '$ratio pixels to one', (tester) async {
      final laidOut = await render(
        tester,
        glyphAtlas: false,
        devicePixelRatio: ratio,
      );
      final stamped = await render(
        tester,
        glyphAtlas: true,
        devicePixelRatio: ratio,
      );
      await dump(tester, laidOut, 'laid_out_$ratio');
      await dump(tester, stamped, 'stamped_$ratio');

      final a = await rgba(tester, laidOut);
      final b = await rgba(tester, stamped);
      final result = compare(a, b, a.sublist(a.length - 4));

      expect(result.laidOut, greaterThan(0.02), reason: 'no text was drawn');
      expect(
        result.stamped,
        closeTo(result.laidOut, result.laidOut * 0.1),
        reason: 'the same glyphs weigh the same',
      );
      expect(
        result.apart,
        lessThan(result.laidOut * 0.6),
        reason: 'and stand in the same places, give or take a pixel',
      );
    });
  }
}
