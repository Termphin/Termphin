import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Pan and zoom state for a [TerminalPane] watching another device's size.
///
/// While watching, the terminal keeps the holder's grid dimensions (`fixedSize`)
/// and starts scaled down to fit the pane. Pinching previews smoothly with a
/// `Transform` and commits a new [committedZoom] when the gesture ends so the
/// terminal re-rasterises glyphs sharply at the zoomed font size without
/// changing the pane's saved font size.
class WatchingZoom {
  /// Maximum zoom factor relative to the pane's normal font size.
  static const double maxZoom = 2.0;

  static const double _zoomEpsilon = 1e-3;
  static const double _minFontSize = 1.0;

  Size _viewportSize = Size.zero;
  ({int columns, int rows})? _fixedSize;
  double _baseFontSize = 12;
  double _lineHeight = 1;
  double _sidePadding = 6;
  double _bottomPadding = 4;

  /// Cell size measured at [_baseFontSize] (zoom 1.0). Null until measured.
  Size? _baseCellSize;

  /// Cell size measured at [_committedZoom], or scaled linearly from
  /// [_baseCellSize] until the new layout finishes.
  Size? _committedCellSize;

  double _minZoom = 1.0;
  double _committedZoom = 1.0;
  double? _previewZoom;
  double _gestureStartZoom = 1.0;
  Offset _panOffset = Offset.zero;
  bool _isFitted = true;

  /// Whether watching mode is active.
  bool get isActive => _fixedSize != null;

  /// Minimum allowed zoom, where the full grid fits inside the viewport.
  double get minZoom => _minZoom;

  /// Zoom factor currently committed to `TerminalView`'s font size.
  double get committedZoom => _committedZoom;

  /// Active zoom factor, including any live pinch preview.
  double get effectiveZoom => _previewZoom ?? _committedZoom;

  /// Whether the view is currently at the fitted zoom.
  bool get isFitted => _isFitted || effectiveZoom <= _minZoom + _zoomEpsilon;

  /// Whether the user has zoomed past the fitted size.
  bool get isZoomedIn => isActive && effectiveZoom > _minZoom + _zoomEpsilon;

  /// Top-left scroll offset of the viewport within the displayed grid.
  Offset get panOffset => _panOffset;

  /// Whether [baseCellSize] has been measured from a laid-out `RenderTerminal`.
  bool get hasMeasuredCellSize => _baseCellSize != null;

  /// Font size passed to `TerminalView` for sharp rasterisation.
  double get renderedFontSize =>
      math.max(_minFontSize, _baseFontSize * _committedZoom);

  /// Horizontal padding scaled with [_committedZoom] so padding stays
  /// proportional to cells across zoom levels.
  double get renderedSidePadding => _sidePadding * _committedZoom;

  /// Bottom padding scaled with [_committedZoom] so it never exceeds a cell at
  /// small fitted zooms.
  double get renderedBottomPadding => _bottomPadding * _committedZoom;

  Size get _fallbackBaseCell =>
      Size(_baseFontSize * 0.6, _baseFontSize * _lineHeight);

  /// Cell size corresponding to [_committedZoom].
  Size get cellSizeAtCommitted {
    final committed = _committedCellSize;
    if (committed != null) return committed;
    final base = _baseCellSize ?? _fallbackBaseCell;
    return Size(base.width * _committedZoom, base.height * _committedZoom);
  }

  /// Unscaled layout size of the `TerminalView` container at [_committedZoom].
  Size get committedGridSize {
    final fixed = _fixedSize;
    if (fixed == null) return Size.zero;
    final cell = cellSizeAtCommitted;
    return Size(
      fixed.columns * cell.width + renderedSidePadding * 2,
      fixed.rows * cell.height + math.max(cell.height, renderedBottomPadding),
    );
  }

  /// Grid size at zoom 1.0 (the pane's normal font size).
  Size get baseGridSize {
    final fixed = _fixedSize;
    if (fixed == null) return Size.zero;
    final cell = _baseCellSize ?? _fallbackBaseCell;
    return Size(
      fixed.columns * cell.width + _sidePadding * 2,
      fixed.rows * cell.height + math.max(cell.height, _bottomPadding),
    );
  }

  /// Scale applied to [committedGridSize] on screen.
  double get displayScale => displayScaleFor(effectiveZoom);

  /// Scale applied to [committedGridSize] for an arbitrary [zoom].
  ///
  /// When at or below [_minZoom], also clamps by the ratio of viewport to
  /// [committedGridSize] so font-hinting rounding or the initial pre-layout
  /// frame never causes the fitted grid to exceed the pane.
  double displayScaleFor(double zoom) {
    if (_committedZoom <= 0) return 1.0;
    var scale = zoom / _committedZoom;
    if (zoom <= _minZoom + _zoomEpsilon &&
        _viewportSize.width > 0 &&
        _viewportSize.height > 0) {
      final grid = committedGridSize;
      if (grid.width > 0 && grid.height > 0) {
        final fit = math.min(
          _viewportSize.width / grid.width,
          _viewportSize.height / grid.height,
        );
        if (fit < scale) scale = fit;
      }
    }
    return scale;
  }

  /// On-screen size of the grid at the current [effectiveZoom].
  Size get displayGridSize => displayGridSizeFor(effectiveZoom);

  /// On-screen size of the grid at [zoom].
  Size displayGridSizeFor(double zoom) =>
      committedGridSize * displayScaleFor(zoom);

  double _computeMinZoom() {
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) return 1.0;
    final base = baseGridSize;
    if (base.width <= 0 || base.height <= 0) return 1.0;
    final fit = math.min(
      _viewportSize.width / base.width,
      _viewportSize.height / base.height,
    );
    return math.min(1.0, fit);
  }

  /// Clamps [offset] so the grid never pans past its edges.
  Offset clampPan(Offset offset, {double? zoom}) {
    final grid = displayGridSizeFor(zoom ?? effectiveZoom);
    final maxX = math.max(0.0, grid.width - _viewportSize.width);
    final maxY = math.max(0.0, grid.height - _viewportSize.height);
    return Offset(offset.dx.clamp(0.0, maxX), offset.dy.clamp(0.0, maxY));
  }

  /// Clears all watching zoom and pan state when control returns to this pane.
  void reset() {
    _fixedSize = null;
    _viewportSize = Size.zero;
    _baseCellSize = null;
    _committedCellSize = null;
    _minZoom = 1.0;
    _committedZoom = 1.0;
    _previewZoom = null;
    _gestureStartZoom = 1.0;
    _panOffset = Offset.zero;
    _isFitted = true;
  }

  /// Drops cached cell measurements when font metrics change.
  void invalidateCellMetrics() {
    _baseCellSize = null;
    _committedCellSize = null;
  }

  /// Seeds the 1x cell size if already measured before entering watching mode.
  void seedBaseCellSize(Size cellSize) {
    if (cellSize.width <= 0 || cellSize.height <= 0) return;
    _baseCellSize = cellSize;
  }

  /// Updates geometry from widget props and layout constraints.
  ///
  /// Recomputes [minZoom] and clamps the current zoom and pan offset when the
  /// holder or viewport resizes.
  void configure({
    required ({int columns, int rows})? fixedSize,
    required Size viewportSize,
    required double baseFontSize,
    required double lineHeight,
    required double sidePadding,
    required double bottomPadding,
  }) {
    if (fixedSize == null) {
      reset();
      return;
    }

    final wasActive = _fixedSize != null;
    if (baseFontSize != _baseFontSize || lineHeight != _lineHeight) {
      invalidateCellMetrics();
    }

    _fixedSize = fixedSize;
    _viewportSize = viewportSize;
    _baseFontSize = baseFontSize;
    _lineHeight = lineHeight;
    _sidePadding = sidePadding;
    _bottomPadding = bottomPadding;
    _minZoom = _computeMinZoom();

    if (!wasActive) {
      _committedZoom = _baseCellSize != null ? _minZoom : 1.0;
      _committedCellSize = _baseCellSize != null
          ? _baseCellSize! * _committedZoom
          : null;
      _previewZoom = null;
      _panOffset = Offset.zero;
      _isFitted = true;
      return;
    }

    if (_isFitted) {
      if (_baseCellSize != null) {
        _committedZoom = _minZoom;
        _committedCellSize = _baseCellSize! * _committedZoom;
      }
      _previewZoom = null;
      _panOffset = Offset.zero;
      return;
    }

    final previousCommitted = _committedZoom;
    _committedZoom = _committedZoom.clamp(_minZoom, maxZoom);
    if (_committedZoom != previousCommitted) {
      _committedCellSize = _baseCellSize != null
          ? _baseCellSize! * _committedZoom
          : null;
    }
    if (_previewZoom != null) {
      _previewZoom = _previewZoom!.clamp(_minZoom, maxZoom);
    }
    _isFitted = effectiveZoom <= _minZoom + _zoomEpsilon;
    _panOffset = _isFitted ? Offset.zero : clampPan(_panOffset);
  }

  /// Records the real [measured] cell size from `RenderTerminal` after layout.
  ///
  /// Returns true when the state changed enough to warrant a rebuild.
  bool updateMeasuredCellSize(Size measured) {
    if (!isActive || measured.width <= 0 || measured.height <= 0) return false;

    if (_baseCellSize == null) {
      final zoom = _committedZoom > 0 ? _committedZoom : 1.0;
      _baseCellSize = Size(measured.width / zoom, measured.height / zoom);
      _minZoom = _computeMinZoom();

      final targetZoom = _isFitted
          ? _minZoom
          : _committedZoom.clamp(_minZoom, maxZoom);
      final changed = (targetZoom - _committedZoom).abs() > 1e-4;
      _committedZoom = targetZoom;
      _committedCellSize = _baseCellSize! * _committedZoom;
      if (_isFitted) _panOffset = Offset.zero;
      return changed;
    }

    final current = _committedCellSize;
    if (current != null &&
        (current.width - measured.width).abs() < 0.05 &&
        (current.height - measured.height).abs() < 0.05) {
      return false;
    }

    final oldGrid = displayGridSize;
    final normX = oldGrid.width > 0 ? _panOffset.dx / oldGrid.width : 0.0;
    final normY = oldGrid.height > 0 ? _panOffset.dy / oldGrid.height : 0.0;

    _committedCellSize = measured;
    if (_isFitted) {
      _panOffset = Offset.zero;
    } else {
      final newGrid = displayGridSize;
      _panOffset = clampPan(
        Offset(normX * newGrid.width, normY * newGrid.height),
      );
    }
    return true;
  }

  /// Captures the starting zoom at the beginning of a scale/pan gesture.
  void startGesture() {
    _gestureStartZoom = effectiveZoom;
  }

  /// Updates the live pinch preview and pan offset around the moving focal
  /// point.
  void updateGesture({
    required double scale,
    required Offset focalInPane,
    required Offset previousFocalInPane,
  }) {
    if (!isActive) return;
    final oldGrid = displayGridSize;
    final newZoom = (_gestureStartZoom * scale).clamp(_minZoom, maxZoom);
    _previewZoom = newZoom;
    _isFitted = newZoom <= _minZoom + _zoomEpsilon;
    if (_isFitted) {
      _panOffset = Offset.zero;
      return;
    }

    final nx = oldGrid.width > 0
        ? (previousFocalInPane.dx + _panOffset.dx) / oldGrid.width
        : 0.0;
    final ny = oldGrid.height > 0
        ? (previousFocalInPane.dy + _panOffset.dy) / oldGrid.height
        : 0.0;
    final newGrid = displayGridSizeFor(newZoom);
    final newGridPoint = Offset(nx * newGrid.width, ny * newGrid.height);
    _panOffset = clampPan(newGridPoint - focalInPane, zoom: newZoom);
  }

  /// Commits the previewed zoom so the terminal re-renders at full sharpness.
  void endGesture() {
    final preview = _previewZoom;
    if (preview == null) return;

    final oldGrid = displayGridSize;
    final normX = oldGrid.width > 0 ? _panOffset.dx / oldGrid.width : 0.0;
    final normY = oldGrid.height > 0 ? _panOffset.dy / oldGrid.height : 0.0;

    _committedZoom = preview.clamp(_minZoom, maxZoom);
    _previewZoom = null;
    _isFitted = _committedZoom <= _minZoom + _zoomEpsilon;
    _committedCellSize = _baseCellSize != null
        ? _baseCellSize! * _committedZoom
        : null;

    if (_isFitted) {
      _panOffset = Offset.zero;
    } else {
      final newGrid = displayGridSize;
      _panOffset = clampPan(
        Offset(normX * newGrid.width, normY * newGrid.height),
      );
    }
  }

  /// Zooms immediately by [factor] around [focalInPane] (desktop wheel /
  /// trackpad).
  void zoomAround({required double factor, required Offset focalInPane}) {
    if (!isActive || factor <= 0) return;
    final oldGrid = displayGridSize;
    final nx = oldGrid.width > 0
        ? (focalInPane.dx + _panOffset.dx) / oldGrid.width
        : 0.0;
    final ny = oldGrid.height > 0
        ? (focalInPane.dy + _panOffset.dy) / oldGrid.height
        : 0.0;

    final nextZoom = (effectiveZoom * factor).clamp(_minZoom, maxZoom);
    _committedZoom = nextZoom;
    _previewZoom = null;
    _isFitted = _committedZoom <= _minZoom + _zoomEpsilon;
    _committedCellSize = _baseCellSize != null
        ? _baseCellSize! * _committedZoom
        : null;

    if (_isFitted) {
      _panOffset = Offset.zero;
    } else {
      final newGrid = displayGridSize;
      final target = Offset(nx * newGrid.width, ny * newGrid.height);
      _panOffset = clampPan(target - focalInPane);
    }
  }

  /// Toggles between fitted zoom and zoom 1.0 centred on [tapInPane].
  /// Zooms all the way out, so the whole grid shows again.
  void fit() {
    if (!isActive) return;
    _committedZoom = _minZoom;
    _previewZoom = null;
    _isFitted = true;
    _committedCellSize = _baseCellSize != null
        ? _baseCellSize! * _committedZoom
        : null;
    _panOffset = Offset.zero;
  }

  void toggleDoubleTap(Offset tapInPane) {
    if (!isActive) return;
    if (!isFitted) {
      fit();
      return;
    }

    final oldGrid = displayGridSize;
    final nx = oldGrid.width > 0
        ? (tapInPane.dx + _panOffset.dx) / oldGrid.width
        : 0.5;
    final ny = oldGrid.height > 0
        ? (tapInPane.dy + _panOffset.dy) / oldGrid.height
        : 0.5;

    final targetZoom = math.max(_minZoom, 1.0);
    _committedZoom = targetZoom;
    _previewZoom = null;
    _isFitted = _committedZoom <= _minZoom + _zoomEpsilon;
    _committedCellSize = _baseCellSize != null
        ? _baseCellSize! * _committedZoom
        : null;

    if (_isFitted) {
      _panOffset = Offset.zero;
      return;
    }

    final newGrid = displayGridSize;
    final targetPoint = Offset(nx * newGrid.width, ny * newGrid.height);
    final paneCenter = Offset(
      _viewportSize.width / 2,
      _viewportSize.height / 2,
    );
    _panOffset = clampPan(targetPoint - paneCenter);
  }

  /// Pans just enough to bring cell ([column], [row]) inside the viewport.
  void revealCell(int column, int row) {
    final fixed = _fixedSize;
    if (fixed == null || _viewportSize.isEmpty) return;

    final col = column.clamp(0, fixed.columns - 1);
    final r = row.clamp(0, fixed.rows - 1);
    final scale = displayScale;
    final cell = cellSizeAtCommitted;
    final cellWidth = cell.width * scale;
    final cellHeight = cell.height * scale;
    final padLeft = renderedSidePadding * scale;

    final left = padLeft + col * cellWidth;
    final right = left + cellWidth;
    final top = r * cellHeight;
    final bottom = top + cellHeight;

    var panX = _panOffset.dx;
    var panY = _panOffset.dy;

    if (left < panX) {
      panX = col == 0 ? 0.0 : left;
    } else if (right > panX + _viewportSize.width) {
      panX = right - _viewportSize.width;
    }

    if (top < panY) {
      panY = top;
    } else if (bottom > panY + _viewportSize.height) {
      panY = bottom - _viewportSize.height;
    }

    _panOffset = clampPan(Offset(panX, panY));
  }
}
