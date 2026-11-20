import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/widgets/terminal/watching_zoom.dart';

void main() {
  group('WatchingZoom', () {
    WatchingZoom createConfigured({
      ({int columns, int rows}) fixedSize = const (columns: 200, rows: 80),
      Size viewportSize = const Size(400, 500),
      double baseFontSize = 12,
      Size baseCellSize = const Size(10, 12),
    }) {
      final zoom = WatchingZoom()..seedBaseCellSize(baseCellSize);
      zoom.configure(
        fixedSize: fixedSize,
        viewportSize: viewportSize,
        baseFontSize: baseFontSize,
        lineHeight: 1,
        sidePadding: 6,
        bottomPadding: 4,
      );
      return zoom;
    }

    test('starts fitted within the viewport', () {
      final zoom = createConfigured();

      expect(zoom.isActive, isTrue);
      expect(zoom.isFitted, isTrue);
      expect(zoom.isZoomedIn, isFalse);
      expect(zoom.panOffset, Offset.zero);
      expect(zoom.displayGridSize.width, lessThanOrEqualTo(400 + 0.01));
      expect(zoom.displayGridSize.height, lessThanOrEqualTo(500 + 0.01));
    });

    test('clamps zoom between minZoom and 2x and keeps pan in bounds', () {
      final zoom = createConfigured();
      final minZoom = zoom.minZoom;

      zoom.startGesture();
      zoom.updateGesture(
        scale: 0.1,
        focalInPane: const Offset(200, 100),
        previousFocalInPane: const Offset(200, 100),
      );
      zoom.endGesture();
      expect(zoom.effectiveZoom, closeTo(minZoom, 1e-6));
      expect(zoom.isFitted, isTrue);
      expect(zoom.panOffset, Offset.zero);

      zoom.startGesture();
      zoom.updateGesture(
        scale: 100,
        focalInPane: const Offset(200, 100),
        previousFocalInPane: const Offset(200, 100),
      );
      zoom.endGesture();
      expect(zoom.effectiveZoom, WatchingZoom.maxZoom);
      expect(zoom.renderedFontSize, 24);
      final maxPanX = zoom.displayGridSize.width - 400;
      final maxPanY = zoom.displayGridSize.height - 500;
      expect(zoom.panOffset.dx, inInclusiveRange(0, maxPanX));
      expect(zoom.panOffset.dy, inInclusiveRange(0, maxPanY));
    });

    test('zoomAround preserves the grid point under the focal point', () {
      final zoom = createConfigured();
      const focal = Offset(150, 80);
      final beforeGrid = zoom.displayGridSize;
      final normBefore = Offset(
        (focal.dx + zoom.panOffset.dx) / beforeGrid.width,
        (focal.dy + zoom.panOffset.dy) / beforeGrid.height,
      );

      zoom.zoomAround(factor: 5, focalInPane: focal);
      final afterGrid = zoom.displayGridSize;
      final normAfter = Offset(
        (focal.dx + zoom.panOffset.dx) / afterGrid.width,
        (focal.dy + zoom.panOffset.dy) / afterGrid.height,
      );

      expect(normAfter.dx, closeTo(normBefore.dx, 1e-3));
      expect(normAfter.dy, closeTo(normBefore.dy, 1e-3));
    });

    test('double-tap toggles between fitted and 1x centred on tap', () {
      final zoom = createConfigured();
      const tap = Offset(300, 120);
      final fittedGrid = zoom.displayGridSize;
      final normTap = Offset(
        tap.dx / fittedGrid.width,
        tap.dy / fittedGrid.height,
      );

      zoom.toggleDoubleTap(tap);
      expect(zoom.effectiveZoom, closeTo(1.0, 1e-6));
      expect(zoom.isZoomedIn, isTrue);

      final zoomedGrid = zoom.displayGridSize;
      final tappedInPane = Offset(
        normTap.dx * zoomedGrid.width - zoom.panOffset.dx,
        normTap.dy * zoomedGrid.height - zoom.panOffset.dy,
      );
      expect(tappedInPane.dx, inInclusiveRange(0, 400));
      expect(tappedInPane.dy, inInclusiveRange(0, 500));

      zoom.toggleDoubleTap(tap);
      expect(zoom.isFitted, isTrue);
      expect(zoom.effectiveZoom, closeTo(zoom.minZoom, 1e-6));
      expect(zoom.panOffset, Offset.zero);
    });

    test('recomputes fitted zoom and clamps when fixedSize changes', () {
      final zoom = createConfigured(fixedSize: const (columns: 200, rows: 80));
      zoom.zoomAround(factor: 2.5, focalInPane: const Offset(200, 100));
      final oldZoom = zoom.effectiveZoom;
      expect(oldZoom, lessThan(1.0));

      zoom.configure(
        fixedSize: const (columns: 50, rows: 20),
        viewportSize: const Size(400, 500),
        baseFontSize: 12,
        lineHeight: 1,
        sidePadding: 6,
        bottomPadding: 4,
      );
      expect(zoom.minZoom, greaterThan(oldZoom));
      expect(zoom.effectiveZoom, closeTo(zoom.minZoom, 1e-6));
    });

    test('reset drops all zoom and pan state', () {
      final zoom = createConfigured();
      zoom.toggleDoubleTap(const Offset(200, 100));
      expect(zoom.isZoomedIn, isTrue);

      zoom.reset();
      expect(zoom.isActive, isFalse);
      expect(zoom.panOffset, Offset.zero);
      expect(zoom.committedZoom, 1.0);
    });

    test('revealCell scrolls off-screen cells in all directions into view', () {
      final zoom = createConfigured(fixedSize: const (columns: 200, rows: 100));
      zoom.toggleDoubleTap(Offset.zero);
      expect(zoom.panOffset, Offset.zero);

      zoom.revealCell(180, 90);
      expect(zoom.panOffset.dx, greaterThan(0));
      expect(zoom.panOffset.dy, greaterThan(0));

      final cell = zoom.cellSizeAtCommitted;
      final padLeft = zoom.renderedSidePadding;
      final rectRight = Rect.fromLTWH(
        padLeft + 180 * cell.width - zoom.panOffset.dx,
        90 * cell.height - zoom.panOffset.dy,
        cell.width,
        cell.height,
      );
      expect(rectRight.left, greaterThanOrEqualTo(0));
      expect(rectRight.right, lessThanOrEqualTo(400));
      expect(rectRight.top, greaterThanOrEqualTo(0));
      expect(rectRight.bottom, lessThanOrEqualTo(500));

      final panAfterRight = zoom.panOffset;
      zoom.revealCell(180, 90);
      expect(zoom.panOffset, panAfterRight);

      zoom.revealCell(2, 1);
      expect(zoom.panOffset.dx, lessThan(panAfterRight.dx));
      expect(zoom.panOffset.dy, lessThan(panAfterRight.dy));
      final rectLeft = Rect.fromLTWH(
        padLeft + 2 * cell.width - zoom.panOffset.dx,
        1 * cell.height - zoom.panOffset.dy,
        cell.width,
        cell.height,
      );
      expect(rectLeft.left, greaterThanOrEqualTo(0));
      expect(rectLeft.top, greaterThanOrEqualTo(0));
    });
  });
}
