import 'dart:collection';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import 'terminal_rendering.dart';

/// Whether this build shows [FrameStatsOverlay] over the terminal, set with
/// `--dart-define=FRAME_STATS=true`. A measuring build, never a release.
const kFrameStats = bool.fromEnvironment('FRAME_STATS');

/// What the last second of frames cost, in the corner of the terminal.
///
/// A release build has no profiler attached, and "it feels slower" cannot be
/// compared from one build to the next. This reads the engine's own frame
/// timings: how many frames were drawn, how long the UI thread and the
/// raster thread spent on one on average, and how many took longer than the
/// display gives a frame. A screen that is not changing draws no frames but
/// the one this redraws itself in, about once a second, so a low count on
/// its own means nothing - the times and the slow ones do.
///
/// A tap switches the terminal between its two ways of drawing text, so the
/// same session can be read both ways within a second of each other.
class FrameStatsOverlay extends StatefulWidget {
  const FrameStatsOverlay({super.key});

  @override
  State<FrameStatsOverlay> createState() => _FrameStatsOverlayState();
}

class _FrameStatsOverlayState extends State<FrameStatsOverlay> {
  static const _window = Duration(seconds: 1);

  final _recent = Queue<FrameTiming>();
  FrameStats _stats = FrameStats.none;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    terminalGlyphAtlas.addListener(_onRendererChanged);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    terminalGlyphAtlas.removeListener(_onRendererChanged);
    super.dispose();
  }

  void _onRendererChanged() {
    if (mounted) setState(() {});
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    _recent.addAll(timings);
    final newest = timings.last.timestampInMicroseconds(
      FramePhase.rasterFinish,
    );
    while (_recent.isNotEmpty &&
        newest -
                _recent.first.timestampInMicroseconds(FramePhase.rasterFinish) >
            _window.inMicroseconds) {
      _recent.removeFirst();
    }
    final refreshRate = View.of(context).display.refreshRate;
    setState(() {
      _stats = FrameStats.of(
        _recent,
        refreshRate: refreshRate > 0 ? refreshRate : 60,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final style = TextStyle(
      fontFamily: AppTheme.monoFamily,
      fontSize: AppTheme.font10,
      color: colors.textPrimary,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => terminalGlyphAtlas.value = !terminalGlyphAtlas.value,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppTheme.radiusXxs),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space6,
            vertical: AppTheme.space2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.frameStats.summary(
                  frames: _stats.frames,
                  ui: _stats.ui.toStringAsFixed(1),
                  raster: _stats.raster.toStringAsFixed(1),
                  slow: _stats.slow,
                ),
                style: style,
              ),
              Text(
                terminalGlyphAtlas.value
                    ? t.frameStats.glyphAtlas
                    : t.frameStats.paragraphs,
                style: style.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A window of frames boiled down to what is worth reading off a corner.
@immutable
class FrameStats {
  const FrameStats({
    required this.frames,
    required this.ui,
    required this.raster,
    required this.slow,
  });

  static const none = FrameStats(frames: 0, ui: 0, raster: 0, slow: 0);

  /// The frames in [timings] against a display refreshing [refreshRate]
  /// times a second: a frame is slow when building and rasterising it took
  /// longer than the display shows one for.
  factory FrameStats.of(
    Iterable<FrameTiming> timings, {
    required double refreshRate,
  }) {
    final budget = Duration.microsecondsPerSecond / refreshRate;
    var frames = 0;
    var ui = 0;
    var raster = 0;
    var slow = 0;
    for (final timing in timings) {
      frames++;
      final built = timing.buildDuration.inMicroseconds;
      final rastered = timing.rasterDuration.inMicroseconds;
      ui += built;
      raster += rastered;
      if (built + rastered > budget) slow++;
    }
    if (frames == 0) return none;
    return FrameStats(
      frames: frames,
      ui: ui / frames / Duration.microsecondsPerMillisecond,
      raster: raster / frames / Duration.microsecondsPerMillisecond,
      slow: slow,
    );
  }

  /// Frames drawn in the window.
  final int frames;

  /// Mean time on the UI thread and on the raster thread, in milliseconds.
  final double ui;
  final double raster;

  /// Frames that took longer than the display shows one for.
  final int slow;
}
