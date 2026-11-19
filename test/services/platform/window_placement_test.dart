import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/platform/desktop_window.dart';

/// A window saved on a monitor that has since been unplugged used to come
/// back where that monitor was - off every screen, with nothing to grab.
void main() {
  const laptop = Rect.fromLTWH(0, 0, 1440, 900);
  const external = Rect.fromLTWH(1440, 0, 2560, 1440);

  test('a window on a screen that is still there goes back where it was', () {
    const saved = Rect.fromLTWH(1600, 100, 1280, 820);
    expect(restorableWindowBounds(saved, [laptop, external]), saved);
  });

  test('a window saved on a monitor that is gone is not put back there', () {
    const saved = Rect.fromLTWH(1600, 100, 1280, 820);
    expect(restorableWindowBounds(saved, [laptop]), isNull);
  });

  test('a title bar mostly off the top or the side is not enough to grab', () {
    expect(
      restorableWindowBounds(const Rect.fromLTWH(1400, 100, 1280, 820), [
        laptop,
      ]),
      isNull,
    );
    expect(
      restorableWindowBounds(const Rect.fromLTWH(200, -400, 1280, 820), [
        laptop,
      ]),
      isNull,
    );
  });

  test('a window larger than the screen it lands on is shrunk to fit it', () {
    final placed = restorableWindowBounds(
      const Rect.fromLTWH(0, 0, 2400, 1400),
      [laptop],
    );
    expect(placed, const Rect.fromLTWH(0, 0, 1440, 900));
  });

  test('no screens reported means no opinion', () {
    const saved = Rect.fromLTWH(3500, 200, 1280, 820);
    expect(restorableWindowBounds(saved, const []), saved);
  });
}
