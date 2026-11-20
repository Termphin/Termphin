import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';

/// The paywall's header art: a glow drawn in ASCII. A band of light drifts
/// and swells with noise, and each cell shows a character as dense as the
/// light under it - from `.` at the edge to `@` at the heart - in the
/// accent, paling towards the heart. The characters flicker, and a finger
/// drawn across them scrambles the ones it passes. Characters only, no
/// gradient behind them.
///
/// Every glyph is drawn once into an atlas and the whole grid goes out in a
/// single [Canvas.drawAtlas], so a frame costs one draw call however many
/// cells there are. The atlas is a white mask rather than a colour anyone
/// sees: each glyph takes its palette colour through [BlendMode.modulate].
/// Still when the system asks for less motion.
class AsciiGlow extends StatefulWidget {
  const AsciiGlow({super.key, this.cellSize = 9, this.quietAround});

  /// Width of one character cell, in logical pixels.
  final double cellSize;

  /// Where a title laid over it sits, if one does: the characters there are
  /// dimmed so it stays readable while the glow carries on around it.
  final Alignment? quietAround;

  /// How tall the paywall's header of it is.
  static const double headerHeight = 196;

  /// The characters from sparse to dense.
  static const ramp = ' .=+xX0S8#@';

  @override
  State<AsciiGlow> createState() => AsciiGlowState();
}

/// Holds the clock, the glyph atlas and the finger's trail.
class AsciiGlowState extends State<AsciiGlow>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);
  final _trail = <_TrailPoint>[];
  ui.Image? _atlas;
  double _atlasScale = 0;
  double _monoFontSize = 0;

  /// Whether the glyph atlas has been drawn.
  @visibleForTesting
  bool get ready => _atlas != null;

  void _tick(Duration elapsed) {
    _time.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final now = _time.value;
    _trail.removeWhere((point) => now - point.at > _TrailPoint.life);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scale = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    if (scale != _atlasScale) {
      _atlasScale = scale;
      _monoFontSize = widget.cellSize * 0.95;
      _buildAtlas(scale);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  Future<void> _buildAtlas(double scale) async {
    final cell = widget.cellSize * scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < AsciiGlow.ramp.length; i++) {
      final painter = TextPainter(
        text: TextSpan(
          text: AsciiGlow.ramp[i],
          style: TextStyle(
            fontFamily: AppTheme.monoFamily,
            fontSize: _monoFontSize * scale,
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
      (cell * AsciiGlow.ramp.length).ceil(),
      cell.ceil(),
    );
    picture.dispose();
    if (!mounted || scale != _atlasScale) {
      image.dispose();
      return;
    }
    setState(() {
      _atlas?.dispose();
      _atlas = image;
    });
  }

  /// A finger at [position] scrambles the characters around it for a
  /// moment.
  void touch(Offset position) {
    _trail.add(_TrailPoint(position, _time.value));
    if (_trail.length > _TrailPoint.max) _trail.removeAt(0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _atlas?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final atlas = _atlas;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: atlas == null
            ? null
            : _AsciiPainter(
                atlas: atlas,
                atlasScale: _atlasScale,
                cellSize: widget.cellSize,
                quietAround: widget.quietAround,
                time: _time,
                trail: _trail,
                accent: colors.primary,
                light: colors.textPrimary,
              ),
      ),
    );
  }
}

class _TrailPoint {
  const _TrailPoint(this.position, this.at);

  static const life = 0.7;
  static const max = 24;

  final Offset position;
  final double at;
}

class _AsciiPainter extends CustomPainter {
  _AsciiPainter({
    required this.atlas,
    required this.atlasScale,
    required this.cellSize,
    required this.quietAround,
    required this.time,
    required this.trail,
    required this.accent,
    required this.light,
  }) : super(repaint: time);

  final ui.Image atlas;
  final double atlasScale;
  final double cellSize;
  final Alignment? quietAround;
  final ValueNotifier<double> time;
  final List<_TrailPoint> trail;
  final Color accent;

  /// What the heart of the glow fades to.
  final Color light;

  static const _density = 0.93;
  static const _glyphOpacity = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final columns = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();
    final palette = [accent, accent, Color.lerp(accent, light, 0.45)!];

    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final tints = <Color>[];
    final atlasCell = cellSize * atlasScale;
    final inverse = 1 / atlasScale;
    final random = Random((t * 24).floor());
    const ramp = AsciiGlow.ramp.length;

    for (var row = 0; row < rows; row++) {
      final v = row / rows;
      for (var column = 0; column < columns; column++) {
        final u = column / columns;
        final seed = _hash(column * 0.137, row * 0.731);
        if (seed > _density) continue;
        var tone = _field(u, v, t, size.aspectRatio);
        final flicker = 0.15 * sin(t * 2.2 + seed * 40);
        tone = (tone + flicker * tone).clamp(0.0, 1.0);
        final cellCenter = Offset(
          (column + 0.5) * cellSize,
          (row + 0.5) * cellSize,
        );
        final scramble = _scramble(cellCenter, t);
        if (tone < 0.06 && scramble < 0.2) continue;
        var index = (tone * (ramp - 1)).round().clamp(1, ramp - 1);
        if (scramble > 0 && random.nextDouble() < scramble) {
          index = 1 + random.nextInt(ramp - 1);
          tone = max(tone, 0.35 * scramble);
        }
        final color = _lerpPalette(palette, tone);
        tints.add(
          color.withValues(
            alpha: _glyphOpacity * min(1, tone * 1.3 + 0.05) * _hush(u, v),
          ),
        );
        rects.add(Rect.fromLTWH(index * atlasCell, 0, atlasCell, atlasCell));
        transforms.add(
          RSTransform.fromComponents(
            rotation: 0,
            scale: inverse,
            anchorX: 0,
            anchorY: 0,
            translateX: column * cellSize,
            translateY: row * cellSize,
          ),
        );
      }
    }
    if (transforms.isEmpty) return;
    canvas.drawAtlas(
      atlas,
      transforms,
      rects,
      tints,
      BlendMode.modulate,
      null,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  /// How bright the light is at ([u], [v]): a horizon band across the
  /// middle, spilling further down than up, whose height and curve breathe, warped by noise so it flows,
  /// with a brighter core wandering along it. Runs up to the top edge,
  /// which is the screen's, and fades out before the bottom one.
  double _field(double u, double v, double t, double aspect) {
    final warpX = _noise(u * 2.4 + t * 0.06, v * 2.4) - 0.5;
    final warpY = _noise(u * 2.4 + 17.3, v * 2.4 - t * 0.05) - 0.5;
    final x = u + warpX * 0.3;
    final y = v + warpY * 0.22;
    final horizon = 0.4 + 0.05 * sin(t * 0.35 + x * 4.0);
    final curve = 0.12 * cos((x - 0.5) * pi);
    final offset = y - horizon + curve;
    final spread = offset > 0 ? 0.42 : 0.24;
    final band = exp(-pow(offset / spread, 2).toDouble());
    final core = exp(
      -(pow((x - 0.5 - 0.18 * sin(t * 0.2)) * 2.2 * aspect.clamp(1.0, 3.0), 2) +
              pow((y - horizon + curve) * 4.0, 2))
          .toDouble(),
    );
    final top = _smooth(-0.15, 0.1, v);
    final bottom = 1 - _smooth(0.8, 1.04, v);
    return ((band * 0.7 + core * 0.55) * top * bottom).clamp(0.0, 1.0);
  }

  /// How much of a character's strength is left at ([u], [v]): all of it,
  /// or with [quietAround] a fifth in an oval around that spot, easing
  /// back to all of it towards the edges.
  double _hush(double u, double v) {
    final quiet = quietAround;
    if (quiet == null) return 1;
    final dx = (u - 0.5 - quiet.x / 2) / 0.56;
    final dy = (v - 0.5 - quiet.y / 2) / 0.3;
    return 1 - 0.8 * exp(-(dx * dx + dy * dy) * 2);
  }

  static double _smooth(double from, double to, double x) {
    final k = ((x - from) / (to - from)).clamp(0.0, 1.0);
    return k * k * (3 - 2 * k);
  }

  double _scramble(Offset cell, double t) {
    var strongest = 0.0;
    for (final point in trail) {
      final age = (t - point.at) / _TrailPoint.life;
      if (age < 0 || age > 1) continue;
      final distance = (cell - point.position).distance / (cellSize * 5);
      final strength = exp(-distance * distance) * (1 - age);
      if (strength > strongest) strongest = strength;
    }
    return strongest;
  }

  static Color _lerpPalette(List<Color> palette, double tone) {
    final scaled = tone * (palette.length - 1);
    final i = scaled.floor().clamp(0, palette.length - 2);
    return Color.lerp(palette[i], palette[i + 1], scaled - i)!;
  }

  static double _hash(double x, double y) {
    final value = sin(x * 127.1 + y * 311.7) * 43758.5453;
    return value - value.floorToDouble();
  }

  static double _noise(double x, double y) {
    final ix = x.floorToDouble();
    final iy = y.floorToDouble();
    final fx = x - ix;
    final fy = y - iy;
    final ux = fx * fx * (3 - 2 * fx);
    final uy = fy * fy * (3 - 2 * fy);
    final a = _hash(ix, iy);
    final b = _hash(ix + 1, iy);
    final c = _hash(ix, iy + 1);
    final d = _hash(ix + 1, iy + 1);
    return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
  }

  @override
  bool shouldRepaint(_AsciiPainter oldDelegate) =>
      oldDelegate.atlas != atlas ||
      oldDelegate.accent != accent ||
      oldDelegate.light != light ||
      oldDelegate.cellSize != cellSize ||
      oldDelegate.quietAround != quietAround;
}
