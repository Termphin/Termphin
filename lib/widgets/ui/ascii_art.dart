import 'dart:math';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';

/// The characters of the ASCII art, from sparse to dense: a cell shows the
/// one as dense as the light under it.
const asciiRamp = ' .=+xX0S8#@';

/// Draws every character of [asciiRamp] once, side by side in cells of
/// [cellSize] logical pixels, at [scale] device pixels each - a white mask,
/// for [Canvas.drawAtlas] to tint with [BlendMode.modulate], so a whole grid
/// of characters goes out in a single draw call.
Future<ui.Image> buildAsciiAtlas(double cellSize, double scale) async {
  final cell = cellSize * scale;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var i = 0; i < asciiRamp.length; i++) {
    final painter = TextPainter(
      text: TextSpan(
        text: asciiRamp[i],
        style: TextStyle(
          fontFamily: AppTheme.monoFamily,
          fontSize: cellSize * 0.95 * scale,
          color: const Color(0xFFFFFFFF),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        i * cell + (cell - painter.width) / 2,
        (cell - painter.height) / 2,
      ),
    );
    painter.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (cell * asciiRamp.length).ceil(),
    cell.ceil(),
  );
  picture.dispose();
  return image;
}

/// A repeatable pseudo-random value in [0, 1) for the point ([x], [y]).
double asciiHash(double x, double y) {
  final value = sin(x * 127.1 + y * 311.7) * 43758.5453;
  return value - value.floorToDouble();
}

/// Smooth value noise in [0, 1) over [asciiHash], for light that drifts
/// rather than jumps.
double asciiNoise(double x, double y) {
  final ix = x.floorToDouble();
  final iy = y.floorToDouble();
  final fx = x - ix;
  final fy = y - iy;
  final ux = fx * fx * (3 - 2 * fx);
  final uy = fy * fy * (3 - 2 * fy);
  final a = asciiHash(ix, iy);
  final b = asciiHash(ix + 1, iy);
  final c = asciiHash(ix, iy + 1);
  final d = asciiHash(ix + 1, iy + 1);
  return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
}

/// Hermite step of [x] between [from] and [to], 0 below and 1 above.
double asciiSmooth(double from, double to, double x) {
  final k = ((x - from) / (to - from)).clamp(0.0, 1.0);
  return k * k * (3 - 2 * k);
}
