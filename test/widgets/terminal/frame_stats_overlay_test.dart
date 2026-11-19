import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/widgets/terminal/frame_stats_overlay.dart';

void main() {
  /// A frame that spent [build] and [raster] microseconds on its two threads.
  FrameTiming frame({required int build, required int raster}) => FrameTiming(
    vsyncStart: 0,
    buildStart: 0,
    buildFinish: build,
    rasterStart: build,
    rasterFinish: build + raster,
    rasterFinishWallTime: build + raster,
  );

  test('no frames is nothing to report, not a division by zero', () {
    final stats = FrameStats.of(const [], refreshRate: 120);

    expect(stats.frames, 0);
    expect(stats.ui, 0);
    expect(stats.raster, 0);
    expect(stats.slow, 0);
  });

  test('averages each thread on its own, in milliseconds', () {
    final stats = FrameStats.of([
      frame(build: 1000, raster: 3000),
      frame(build: 3000, raster: 5000),
    ], refreshRate: 60);

    expect(stats.frames, 2);
    expect(stats.ui, 2);
    expect(stats.raster, 4);
  });

  test('a frame is slow against the display it was drawn for', () {
    final frames = [
      frame(build: 2000, raster: 3000),
      frame(build: 4000, raster: 6000),
      frame(build: 9000, raster: 9000),
    ];

    expect(FrameStats.of(frames, refreshRate: 60).slow, 1);
    expect(FrameStats.of(frames, refreshRate: 120).slow, 2);
  });
}
