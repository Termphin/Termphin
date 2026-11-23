import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/assistant/assistant_session.dart';
import '../../theme/theme.dart';
import '../ui/ascii_art.dart';

/// The assistant's face: a ring of light drawn in ASCII, in the same
/// characters and accent as the paywall's glow. The ring drifts with noise
/// and a brighter arc travels round it; [mood] sets how fast, how restless
/// and in which colour, and a change of mood eases over rather than jumps.
///
/// One [Canvas.drawAtlas] a frame, like the glow. Still when the system asks
/// for less motion.
class AssistantOrb extends StatefulWidget {
  const AssistantOrb({
    super.key,
    required this.size,
    this.mood = AssistantMood.idle,
    this.animate = true,
  });

  /// Width and height of the orb, in logical pixels.
  final double size;

  final AssistantMood mood;

  /// Whether it moves at all. An orb left on screen while nothing happens -
  /// the minimised assistant at rest - holds still rather than drawing
  /// frames for nobody.
  final bool animate;

  @override
  State<AssistantOrb> createState() => _AssistantOrbState();
}

class _AssistantOrbState extends State<AssistantOrb>
    with SingleTickerProviderStateMixin {
  static const _change = 0.7;

  late final Ticker _ticker = createTicker(_tick);
  final _clock = _OrbClock();
  ui.Image? _atlas;
  double _atlasScale = 0;
  double _atlasCell = 0;
  Duration _last = Duration.zero;

  late _MoodStyle _from = _MoodStyle.of(widget.mood);
  late _MoodStyle _to = _from;
  double _blend = 1;

  double get _cellSize => max(5.0, widget.size / 17);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureAtlas();
    _syncTicker();
  }

  void _syncTicker() {
    final moving = widget.animate && !MediaQuery.disableAnimationsOf(context);
    if (!moving) {
      if (_ticker.isActive) _ticker.stop();
      _blend = 1;
      _clock.still(_style);
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(AssistantOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.size != widget.size) _ensureAtlas();
    if (oldWidget.animate != widget.animate) _syncTicker();
    if (oldWidget.mood != widget.mood) {
      _from = _style;
      _to = _MoodStyle.of(widget.mood);
      _blend = 0;
      if (!_ticker.isActive) {
        _blend = 1;
        _clock.still(_style);
      }
    }
  }

  _MoodStyle get _style =>
      _MoodStyle.lerp(_from, _to, Curves.easeInOut.transform(_blend));

  void _ensureAtlas() {
    final scale = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    if (scale == _atlasScale && _cellSize == _atlasCell) return;
    _atlasScale = scale;
    _atlasCell = _cellSize;
    buildAsciiAtlas(_atlasCell, scale).then((image) {
      if (!mounted || scale != _atlasScale || _atlasCell != _cellSize) {
        image.dispose();
        return;
      }
      setState(() {
        _atlas?.dispose();
        _atlas = image;
      });
    });
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 0.0
        : (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    if (_blend < 1) _blend = min(1, _blend + dt / _change);
    _clock.advance(dt, _style);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _atlas?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final atlas = _atlas;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: atlas == null
            ? null
            : CustomPaint(
                painter: _OrbPainter(
                  atlas: atlas,
                  atlasScale: _atlasScale,
                  cellSize: _atlasCell,
                  clock: _clock,
                  palette: _OrbPalette(
                    idle: colors.primary,
                    waiting: colors.warning,
                    done: colors.success,
                    failed: colors.error,
                    light: colors.textPrimary,
                  ),
                ),
              ),
      ),
    );
  }
}

/// How one mood moves. Everything is a number so two moods blend.
class _MoodStyle {
  const _MoodStyle({
    required this.flow,
    required this.spin,
    required this.thickness,
    required this.core,
    required this.ripple,
    required this.churn,
    required this.pulse,
    required this.glow,
    required this.tint,
  });

  /// How fast the noise under the ring drifts.
  final double flow;

  /// How fast the bright arc travels round, in radians a second.
  final double spin;

  /// How wide the ring is, as a share of the radius.
  final double thickness;

  /// How bright the middle glows.
  final double core;

  /// How strong the rings rippling outwards are.
  final double ripple;

  /// The share of characters swapped for a random one each frame.
  final double churn;

  /// How deep the ring breathes.
  final double pulse;

  /// Overall brightness.
  final double glow;

  /// Weights of the idle, waiting, done and failed colours.
  final List<double> tint;

  static _MoodStyle of(AssistantMood mood) => switch (mood) {
    AssistantMood.idle => const _MoodStyle(
      flow: 0.10,
      spin: 0.7,
      thickness: 0.10,
      core: 0,
      ripple: 0,
      churn: 0,
      pulse: 0.03,
      glow: 0.8,
      tint: [1, 0, 0, 0],
    ),
    AssistantMood.thinking => const _MoodStyle(
      flow: 0.45,
      spin: 3.2,
      thickness: 0.13,
      core: 0.35,
      ripple: 0,
      churn: 0.22,
      pulse: 0.02,
      glow: 1,
      tint: [1, 0, 0, 0],
    ),
    AssistantMood.working => const _MoodStyle(
      flow: 0.22,
      spin: 1.6,
      thickness: 0.11,
      core: 0.12,
      ripple: 0.85,
      churn: 0.05,
      pulse: 0,
      glow: 0.95,
      tint: [1, 0, 0, 0],
    ),
    AssistantMood.waiting => const _MoodStyle(
      flow: 0.06,
      spin: 0.4,
      thickness: 0.12,
      core: 0.1,
      ripple: 0,
      churn: 0,
      pulse: 0.09,
      glow: 0.95,
      tint: [0, 1, 0, 0],
    ),
    AssistantMood.done => const _MoodStyle(
      flow: 0.05,
      spin: 0.25,
      thickness: 0.10,
      core: 0,
      ripple: 0,
      churn: 0,
      pulse: 0.02,
      glow: 0.85,
      tint: [0, 0, 1, 0],
    ),
    AssistantMood.failed => const _MoodStyle(
      flow: 0.03,
      spin: 0,
      thickness: 0.10,
      core: 0,
      ripple: 0,
      churn: 0,
      pulse: 0,
      glow: 0.8,
      tint: [0, 0, 0, 1],
    ),
  };

  static _MoodStyle lerp(_MoodStyle a, _MoodStyle b, double k) {
    double mix(double x, double y) => x + (y - x) * k;
    return _MoodStyle(
      flow: mix(a.flow, b.flow),
      spin: mix(a.spin, b.spin),
      thickness: mix(a.thickness, b.thickness),
      core: mix(a.core, b.core),
      ripple: mix(a.ripple, b.ripple),
      churn: mix(a.churn, b.churn),
      pulse: mix(a.pulse, b.pulse),
      glow: mix(a.glow, b.glow),
      tint: [for (var i = 0; i < 4; i++) mix(a.tint[i], b.tint[i])],
    );
  }
}

/// The orb's running phases. Each advances by its own speed, so a change of
/// speed bends the motion instead of making it jump.
class _OrbClock extends ChangeNotifier {
  double time = 0;
  double flow = 0;
  double spin = 0;
  double ripple = 0;
  _MoodStyle style = _MoodStyle.of(AssistantMood.idle);

  void advance(double dt, _MoodStyle now) {
    time += dt;
    flow += dt * now.flow;
    spin += dt * now.spin;
    ripple += dt * 0.55;
    style = now;
    notifyListeners();
  }

  void still(_MoodStyle now) {
    time = 12;
    flow = 1.2;
    spin = 1;
    ripple = 0.4;
    style = now;
    notifyListeners();
  }
}

class _OrbPalette {
  const _OrbPalette({
    required this.idle,
    required this.waiting,
    required this.done,
    required this.failed,
    required this.light,
  });

  final Color idle;
  final Color waiting;
  final Color done;
  final Color failed;

  /// What the brightest characters pale towards.
  final Color light;

  Color base(List<double> tint) {
    final total = tint.fold<double>(0, (a, b) => a + b);
    var r = 0.0, g = 0.0, b = 0.0;
    for (final (i, color) in [idle, waiting, done, failed].indexed) {
      final w = tint[i] / total;
      r += color.r * w;
      g += color.g * w;
      b += color.b * w;
    }
    return Color.from(alpha: 1, red: r, green: g, blue: b);
  }

  @override
  bool operator ==(Object other) =>
      other is _OrbPalette &&
      other.idle == idle &&
      other.waiting == waiting &&
      other.done == done &&
      other.failed == failed &&
      other.light == light;

  @override
  int get hashCode => Object.hash(idle, waiting, done, failed, light);
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.atlas,
    required this.atlasScale,
    required this.cellSize,
    required this.clock,
    required this.palette,
  }) : super(repaint: clock);

  final ui.Image atlas;
  final double atlasScale;
  final double cellSize;
  final _OrbClock clock;
  final _OrbPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final style = clock.style;
    final t = clock.time;
    final radius = min(size.width, size.height) / 2;
    final boost = 1 - asciiSmooth(_compact, _full, radius * 2);
    final base = palette.base(style.tint);
    final pale = Color.lerp(base, palette.light, 0.5)!;
    final columns = (size.width / cellSize).floor();
    final rows = (size.height / cellSize).floor();
    final offsetX = (size.width - columns * cellSize) / 2;
    final offsetY = (size.height - rows * cellSize) / 2;
    final center = size.center(Offset.zero);
    final atlasCell = cellSize * atlasScale;
    final inverse = 1 / atlasScale;
    final random = Random((t * 20).floor());
    const ramp = asciiRamp.length;

    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final tints = <Color>[];
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final x = offsetX + (column + 0.5) * cellSize;
        final y = offsetY + (row + 0.5) * cellSize;
        final dx = (x - center.dx) / radius;
        final dy = (y - center.dy) / radius;
        final r = sqrt(dx * dx + dy * dy);
        if (r > 1.02) continue;
        final seed = asciiHash(column * 0.137, row * 0.731);
        var tone = _field(r, atan2(dy, dx), t, style, 1 + boost * 0.6);
        tone = (tone + 0.15 * sin(t * 2.2 + seed * 40) * tone).clamp(0.0, 1.0);
        if (tone < 0.07) continue;
        var index = (tone * (ramp - 1)).round().clamp(1, ramp - 1);
        if (style.churn > 0 && random.nextDouble() < style.churn * tone) {
          index = 1 + random.nextInt(ramp - 1);
        }
        final color = Color.lerp(base, pale, max(0, tone * 2 - 1))!;
        tints.add(
          color.withValues(
            alpha: min(1, tone * (1.4 + boost) + 0.08 + boost / 6),
          ),
        );
        rects.add(Rect.fromLTWH(index * atlasCell, 0, atlasCell, atlasCell));
        transforms.add(
          RSTransform.fromComponents(
            rotation: 0,
            scale: inverse,
            anchorX: 0,
            anchorY: 0,
            translateX: x - cellSize / 2,
            translateY: y - cellSize / 2,
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

  /// How bright the light is at radius [r] (1 at the edge) and angle
  /// [theta], the ring [widen]ed for a small orb: a ring warped by noise with a bright arc travelling round it,
  /// a glow in the middle, and rings rippling outwards - each as strong as
  /// [style] makes it.
  double _field(
    double r,
    double theta,
    double t,
    _MoodStyle style,
    double widen,
  ) {
    final c = cos(theta);
    final s = sin(theta);
    final wobble =
        (asciiNoise(c * 1.7 + clock.flow * 3, s * 1.7 - clock.flow * 2.4) -
            0.5) *
        0.26;
    final ring = 0.66 + wobble + style.pulse * sin(t * 2.4);
    final band = exp(
      -pow((r - ring) / (style.thickness * widen), 2).toDouble(),
    );
    final arc = pow(0.5 + 0.5 * cos(theta - clock.spin), 3).toDouble();
    var tone = band * (0.4 + 0.6 * arc);
    if (style.core > 0) {
      final flicker = 0.7 + 0.3 * sin(t * 4.1 + r * 9);
      tone += style.core * exp(-pow(r / 0.36, 2).toDouble()) * flicker;
    }
    if (style.ripple > 0) {
      for (final lag in const [0.0, 0.5]) {
        final p = (clock.ripple + lag) % 1;
        final at = 0.15 + p * 0.85;
        tone +=
            style.ripple *
            exp(-pow((r - at) / 0.07, 2).toDouble()) *
            (1 - p) *
            0.7;
      }
    }
    tone *= style.glow * (1 - asciiSmooth(0.9, 1.02, r));
    return tone.clamp(0.0, 1.0);
  }

  /// Below this size the ring is thicker and brighter, since a few cells
  /// of faint characters would read as dust; from [_full] up it is as
  /// drawn.
  static const _compact = 40.0;
  static const _full = 96.0;

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) =>
      oldDelegate.atlas != atlas ||
      oldDelegate.cellSize != cellSize ||
      oldDelegate.palette != palette;
}
