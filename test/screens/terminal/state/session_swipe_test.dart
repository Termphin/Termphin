import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/screens/terminal/state/session_swipe.dart';

const _width = 400.0;

/// Past `_maxCommitDistance` (96) and past `width * 0.22` (88), so a drag this
/// far commits on distance alone however slowly it was made.
const _farEnough = 120.0;

/// Under both, so only velocity can commit it.
const _shortDrag = 40.0;

class _Harness {
  _Harness({
    required TickerProvider vsync,
    int tabCount = 3,
    int activeIndex = 1,
    bool blocked = false,
  }) : _tabCount = tabCount,
       _activeIndex = activeIndex,
       _blocked = blocked {
    controller = SessionSwipeController(
      vsync: vsync,
      tabCount: () => _tabCount,
      activeIndex: () => _activeIndex,
      onCommit: committed.add,
      isBlocked: () => _blocked,
    )..viewportWidth = _width;
  }

  late final SessionSwipeController controller;
  final List<int> committed = [];
  int _tabCount;
  int _activeIndex;
  bool _blocked;

  set blocked(bool value) => _blocked = value;
  set tabCount(int value) => _tabCount = value;

  static const _origin = Offset(200, 300);

  void down({int pointer = 1, Duration at = Duration.zero}) {
    controller.onPointerDown(
      PointerDownEvent(pointer: pointer, position: _origin, timeStamp: at),
    );
  }

  void move(
    double dx, {
    double dy = 0,
    int pointer = 1,
    Duration at = Duration.zero,
  }) {
    controller.onPointerMove(
      PointerMoveEvent(
        pointer: pointer,
        position: _origin + Offset(dx, dy),
        timeStamp: at,
      ),
    );
  }

  void up(double dx, {int pointer = 1, required Duration at}) {
    controller.onPointerUp(
      PointerUpEvent(
        pointer: pointer,
        position: _origin + Offset(dx, 0),
        timeStamp: at,
      ),
    );
  }

  /// One drag, start to finish. [elapsed] is what the velocity is measured
  /// over, so it decides whether a short drag counts as a flick.
  void swipe(double dx, {Duration elapsed = const Duration(seconds: 1)}) {
    down();
    move(dx, at: elapsed);
    up(dx, at: elapsed);
  }

  void dispose() => controller.dispose();
}

void main() {
  group('SessionSwipeController', () {
    late _Harness harness;

    Future<_Harness> build(
      WidgetTester tester, {
      int tabCount = 3,
      int activeIndex = 1,
      bool blocked = false,
    }) async {
      late TickerProvider vsync;
      await tester.pumpWidget(
        _VSyncProbe(onReady: (provider) => vsync = provider),
      );
      harness = _Harness(
        vsync: vsync,
        tabCount: tabCount,
        activeIndex: activeIndex,
        blocked: blocked,
      );
      addTearDown(harness.dispose);
      return harness;
    }

    group('a tapped tab slides in', () {
      testWidgets('from the right when it lies to the right', (tester) async {
        final h = await build(tester, activeIndex: 2);

        h.controller.slideIn(from: 1, to: 2);

        expect(h.controller.targetIndex, 1);
        expect(h.controller.offset.value, _width);
        expect(h.controller.isAnimating, isTrue);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        final midway = h.controller.offset.value;
        expect(midway, inExclusiveRange(0, _width));

        await tester.pumpAndSettle();
        expect(h.controller.offset.value, 0);
        expect(h.controller.targetIndex, isNull);
        expect(h.committed, isEmpty, reason: 'the tap already switched');
      });

      testWidgets('from the left when it lies to the left', (tester) async {
        final h = await build(tester, activeIndex: 0);

        h.controller.slideIn(from: 2, to: 0);

        expect(h.controller.offset.value, -_width);
        await tester.pumpAndSettle();
        expect(h.controller.offset.value, 0);
      });

      testWidgets('not for the tab already showing', (tester) async {
        final h = await build(tester);

        h.controller.slideIn(from: 1, to: 1);

        expect(h.controller.isAnimating, isFalse);
        expect(h.controller.targetIndex, isNull);
      });

      testWidgets('not before the viewport is measured', (tester) async {
        final h = await build(tester);
        h.controller.viewportWidth = 0;

        h.controller.slideIn(from: 0, to: 1);

        expect(h.controller.isAnimating, isFalse);
        expect(h.controller.offset.value, 0);
      });

      testWidgets('not under a finger already dragging', (tester) async {
        final h = await build(tester);
        h.down();

        h.controller.slideIn(from: 0, to: 1);

        expect(h.controller.isAnimating, isFalse);
      });

      testWidgets('a second tap mid-slide starts over from where it left', (
        tester,
      ) async {
        final h = await build(tester, activeIndex: 1);
        h.controller.slideIn(from: 0, to: 1);
        await tester.pump(const Duration(milliseconds: 60));

        h.controller.slideIn(from: 1, to: 2);
        expect(h.controller.targetIndex, 1);
        expect(h.controller.offset.value, _width);

        await tester.pumpAndSettle();
        expect(h.controller.offset.value, 0);
        expect(h.controller.targetIndex, isNull);
        expect(h.committed, isEmpty);
      });

      testWidgets('a swipe can follow once it has landed', (tester) async {
        final h = await build(tester);
        h.controller.slideIn(from: 0, to: 1);
        await tester.pumpAndSettle();

        h.swipe(-_farEnough);
        await tester.pumpAndSettle();

        expect(h.committed, [2]);
      });
    });

    testWidgets('a drag past the lock distance takes the next tab', (
      tester,
    ) async {
      final h = await build(tester);
      h.down();
      h.move(-_farEnough);
      expect(h.controller.targetIndex, 2);
      expect(h.controller.offset.value, -_farEnough);

      h.up(-_farEnough, at: const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(h.committed, [2]);
      expect(h.controller.offset.value, 0);
      expect(h.controller.targetIndex, isNull);
    });

    testWidgets('dragging right takes the previous tab', (tester) async {
      final h = await build(tester);
      h.swipe(_farEnough);
      await tester.pumpAndSettle();
      expect(h.committed, [0]);
    });

    testWidgets('a short slow drag springs back without committing', (
      tester,
    ) async {
      final h = await build(tester);
      h.swipe(-_shortDrag);
      await tester.pumpAndSettle();
      expect(h.committed, isEmpty);
      expect(h.controller.offset.value, 0);
    });

    testWidgets('the same short drag commits when it is a flick', (
      tester,
    ) async {
      final h = await build(tester);
      h.swipe(-_shortDrag, elapsed: const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(h.committed, [2]);
    });

    testWidgets('a drag under the lock distance is a tap, not a swipe', (
      tester,
    ) async {
      final h = await build(tester);
      h.down();
      h.move(-8);
      expect(h.controller.targetIndex, isNull);
      expect(h.controller.offset.value, 0);

      h.up(-8, at: const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(h.committed, isEmpty);
    });

    testWidgets('a mostly vertical drag is a scroll, not a swipe', (
      tester,
    ) async {
      final h = await build(tester);
      h.down();
      h.move(-20, dy: 40);
      expect(h.controller.targetIndex, isNull);

      h.move(-_farEnough, dy: 40);
      expect(h.controller.targetIndex, isNull);

      h.up(-_farEnough, at: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(h.committed, isEmpty);
    });

    testWidgets('rubber-bands at the first tab and does not commit', (
      tester,
    ) async {
      final h = await build(tester, activeIndex: 0);
      h.down();
      h.move(_farEnough);
      expect(h.controller.targetIndex, isNull, reason: 'nowhere to go left');
      expect(h.controller.offset.value, closeTo(_farEnough * 0.18, 0.001));

      h.up(_farEnough, at: const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(h.committed, isEmpty);
    });

    testWidgets('rubber-bands at the last tab too', (tester) async {
      final h = await build(tester, activeIndex: 2);
      h.down();
      h.move(-_farEnough);
      expect(h.controller.targetIndex, isNull);
      expect(h.controller.offset.value, closeTo(-_farEnough * 0.18, 0.001));
    });

    testWidgets('does nothing with a single tab', (tester) async {
      final h = await build(tester, tabCount: 1, activeIndex: 0);
      h.swipe(-_farEnough);
      await tester.pumpAndSettle();
      expect(h.committed, isEmpty);
      expect(h.controller.offset.value, 0);
    });

    testWidgets('does not steal a pointer something else owns', (tester) async {
      final h = await build(tester, blocked: true);
      h.swipe(-_farEnough);
      await tester.pumpAndSettle();
      expect(h.committed, isEmpty);
      expect(h.controller.offset.value, 0);
    });

    testWidgets('gives the pointer up when a handle is grabbed mid-drag', (
      tester,
    ) async {
      final h = await build(tester);
      h.down();
      h.move(-_farEnough);
      expect(h.controller.targetIndex, 2);

      h.blocked = true;
      h.move(-_farEnough - 10);
      await tester.pumpAndSettle();
      expect(h.controller.offset.value, 0);

      h.up(-_farEnough - 10, at: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(h.committed, isEmpty);
    });

    testWidgets('ignores events from a pointer it is not following', (
      tester,
    ) async {
      final h = await build(tester);
      h.down(pointer: 1);
      h.move(-_farEnough, pointer: 2);
      expect(h.controller.targetIndex, isNull);
      expect(h.controller.offset.value, 0);

      h.up(-_farEnough, pointer: 2, at: const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(h.committed, isEmpty);
    });

    testWidgets('a second finger cancels rather than fighting the first', (
      tester,
    ) async {
      final h = await build(tester);
      h.down(pointer: 1);
      h.move(-_farEnough, pointer: 1);
      h.down(pointer: 2);
      await tester.pumpAndSettle();

      expect(h.controller.offset.value, 0);
      expect(h.controller.targetIndex, isNull);
      expect(h.committed, isEmpty);
    });

    testWidgets('clamps the offset to one viewport', (tester) async {
      final h = await build(tester);
      h.down();
      h.move(-_width * 3);
      expect(h.controller.offset.value, -_width);
    });

    testWidgets('cancel() springs back and commits nothing', (tester) async {
      final h = await build(tester);
      h.down();
      h.move(-_farEnough);
      h.controller.cancel();
      await tester.pumpAndSettle();
      expect(h.controller.offset.value, 0);
      expect(h.committed, isEmpty);
    });

    testWidgets('reports no commit when the target is already active', (
      tester,
    ) async {
      final h = await build(tester);
      h.down();
      h.move(-_farEnough);
      h._activeIndex = 2;
      h.up(-_farEnough, at: const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(h.committed, [2]);
    });

    testWidgets('a new drag is refused while the last one is animating', (
      tester,
    ) async {
      final h = await build(tester);
      h.swipe(-_farEnough);
      await tester.pump(const Duration(milliseconds: 40));
      expect(h.controller.isAnimating, isTrue);

      h.down(pointer: 5);
      h.move(_farEnough, pointer: 5);
      expect(h.controller.targetIndex, 2, reason: 'still the first gesture');

      await tester.pumpAndSettle();
      expect(h.committed, [2]);
    });

    testWidgets('measures nothing until the viewport width is known', (
      tester,
    ) async {
      final h = await build(tester);
      h.controller.viewportWidth = 0;
      h.down();
      h.move(-_farEnough);
      expect(h.controller.targetIndex, 2);
      expect(h.controller.offset.value, 0);
    });
  });
}

/// Hands out a real [TickerProvider] so the controller's animation is driven
/// by the test's own frames.
class _VSyncProbe extends StatefulWidget {
  const _VSyncProbe({required this.onReady});

  final void Function(TickerProvider vsync) onReady;

  @override
  State<_VSyncProbe> createState() => _VSyncProbeState();
}

class _VSyncProbeState extends State<_VSyncProbe>
    with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.onReady(this);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
