import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/theme/theme.dart';

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG contrast ratio, 1.0 (identical) to 21.0 (black on white).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The palettes are tuned by number, not by eye, so the numbers are the test.
///
/// Both directions matter. Too little contrast is unreadable; too much is the
/// glare and the wireframe-grid look that comes from paper-white text on black
/// and a stroke drawn around every container.
void main() {
  for (final entry in {
    'dark': AppColors.dark,
    'light': AppColors.light,
  }.entries) {
    final name = entry.key;
    final c = entry.value;

    test('$name text is legible without glaring', () {
      expect(_contrast(c.textPrimary, c.surfaceCard), inInclusiveRange(12, 16));
      expect(_contrast(c.textSecondary, c.surfaceCard), inInclusiveRange(7, 9));
      expect(
        _contrast(c.textTertiary, c.surfaceCard),
        inInclusiveRange(4.5, 5.5),
      );
      expect(
        _contrast(c.textTertiary, c.backgroundPrimary),
        greaterThanOrEqualTo(4.2),
      );
    });

    test('$name separates by surface, not by stroke', () {
      expect(
        _contrast(c.surfaceCard, c.backgroundPrimary),
        greaterThanOrEqualTo(1.08),
      );
      expect(_contrast(c.surfaceBorder, c.surfaceCard), lessThan(1.35));
      expect(
        _contrast(c.surfaceBorderStrong, c.surfaceCard),
        greaterThan(_contrast(c.surfaceBorder, c.surfaceCard)),
      );
      expect(_contrast(c.surfaceDivider, c.surfaceCard), lessThan(1.2));
      expect(
        _contrast(c.primaryHighlight, c.backgroundPrimary),
        greaterThanOrEqualTo(1.15),
      );
      expect(
        _contrast(c.primaryHighlight, c.surfaceCard),
        greaterThanOrEqualTo(1.08),
      );
    });

    test('$name accent and status colours clear AA on both surfaces', () {
      for (final on in [c.surfaceCard, c.backgroundPrimary]) {
        expect(_contrast(c.primary, on), greaterThanOrEqualTo(4.3));
        expect(_contrast(c.error, on), greaterThanOrEqualTo(4.3));
        expect(_contrast(c.success, on), greaterThanOrEqualTo(4.3));
        expect(_contrast(c.warning, on), greaterThanOrEqualTo(4.3));
      }
      expect(_contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
      expect(_contrast(c.primary, c.primaryHighlight), greaterThanOrEqualTo(4));
    });
  }
}
