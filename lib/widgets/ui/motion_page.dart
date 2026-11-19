import 'package:flutter/widgets.dart';

/// Paging that respects a desktop's zero motion.
///
/// A [PageController] asked to animate over no time does not move: the
/// scroll animation asserts on a zero duration in debug and, in release,
/// leaves the page where it was - a Next button that does nothing. These
/// jump instead when there is no time to animate in.
extension MotionPages on PageController {
  Future<void> goToPage(
    int page, {
    required Duration duration,
    required Curve curve,
  }) async {
    if (duration == Duration.zero) {
      jumpToPage(page);
      return;
    }
    await animateToPage(page, duration: duration, curve: curve);
  }

  Future<void> goToNextPage({
    required Duration duration,
    required Curve curve,
  }) => goToPage(_current + 1, duration: duration, curve: curve);

  Future<void> goToPreviousPage({
    required Duration duration,
    required Curve curve,
  }) => goToPage(_current - 1, duration: duration, curve: curve);

  int get _current => (page ?? initialPage.toDouble()).round();
}
