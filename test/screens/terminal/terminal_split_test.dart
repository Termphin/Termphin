import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/screens/terminal/terminal_screen.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/terminal/session_view.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

/// Swapping two panes is a drag: it must hold past the terminal's own
/// double-tap window before moving, or it reads as a tap. A folded pane is
/// clipped rather than resized, so its shell is never told the window
/// changed mid-animation.
void main() {
  Future<void> openTwoTabs(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final profile = profileFixture();
    final second = profileFixture(
      id: 'profile-2',
      name: 'Machine 2',
      host: 'machine-2.example.com',
    );
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(
          FakeProfileStorage([profile, second]),
        ),
      ],
    );
    addTearDown(manager.dispose);
    container.read(profilesProvider);
    await container.read(profilesProvider.notifier).loadProfiles();

    await pumpTestApp(
      tester,
      TerminalScreen(initialSessionId: 'session-1', initialProfile: profile),
      container: container,
    );
    await backend.connectCalled.future;
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('tabBarAddButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Machine 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder tabContent(String id) => find.byKey(ValueKey('sessionTabContent-$id'));

  String secondId(WidgetTester tester) {
    final element = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'sessionTabContent-',
              ) &&
              (w.key! as ValueKey<String>).value !=
                  'sessionTabContent-session-1',
        )
        .evaluate()
        .single;
    return (element.widget.key! as ValueKey<String>).value.substring(
      'sessionTabContent-'.length,
    );
  }

  Future<void> openMenu(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('tabMenu-$id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> splitViaMenu(WidgetTester tester, String other) async {
    await openMenu(tester, 'session-1');
    await tester.tap(find.text('Split screen with…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('splitCandidate-$other')));
    await tester.pumpAndSettle();
  }

  bool isActive(WidgetTester tester, String id) => tester
      .widget<SessionView>(
        find.descendant(
          of: find.byKey(ValueKey('splitPane-$id')),
          matching: find.byType(SessionView),
        ),
      )
      .isActive;

  testWidgets('a split stacks its panes in portrait', (tester) async {
    await openTwoTabs(tester);
    final other = secondId(tester);

    await splitViaMenu(tester, other);

    expect(find.byKey(const ValueKey('splitTab-session-1')), findsOneWidget);
    final top = tester.getRect(
      find.byKey(const ValueKey('splitPane-session-1')),
    );
    final bottom = tester.getRect(find.byKey(ValueKey('splitPane-$other')));
    expect(top.bottom, lessThanOrEqualTo(bottom.top));
    expect(top.left, bottom.left);
    expect(isActive(tester, other), isTrue);
    expect(isActive(tester, 'session-1'), isFalse);

    await tester.tapAt(top.center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(isActive(tester, 'session-1'), isTrue);
    expect(isActive(tester, other), isFalse);
  });

  testWidgets('side by side in landscape', (tester) async {
    await openTwoTabs(tester);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final other = secondId(tester);

    await splitViaMenu(tester, other);

    final left = tester.getRect(
      find.byKey(const ValueKey('splitPane-session-1')),
    );
    final right = tester.getRect(find.byKey(ValueKey('splitPane-$other')));
    expect(left.right, lessThanOrEqualTo(right.left));
    expect(left.top, right.top);
    final bar = tester.getCenter(find.byKey(ValueKey('splitHeader-$other')));
    final gesture = await tester.startGesture(bar);
    await tester.pump(const Duration(milliseconds: 600));
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(Offset.lerp(bar, left.center, step / 8)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(ValueKey('splitPane-$other'))).right,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('splitPane-session-1'))).left,
      ),
    );
  });

  testWidgets('the tab menu makes a split and takes it apart again', (
    tester,
  ) async {
    await openTwoTabs(tester);
    final other = secondId(tester);

    final tabHeight = tester.getSize(tabContent('session-1')).height;
    await openMenu(tester, 'session-1');
    await tester.tap(find.text('Split screen with…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('splitCandidate-$other')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('splitTab-session-1')), findsOneWidget);
    expect(find.byKey(ValueKey('splitPane-$other')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('splitTab-session-1'))).height,
      tabHeight,
    );
    expect(tester.getSize(tabContent('session-1')).height, tabHeight);
    expect(tester.getSize(tabContent(other)).height, tabHeight);

    /// The pane brought in lands below; a swap puts it on top.
    Rect paneRect(String id) =>
        tester.getRect(find.byKey(ValueKey('splitPane-$id')));
    expect(paneRect('session-1').top, lessThan(paneRect(other).top));
    final bar = tester.getCenter(find.byKey(ValueKey('splitHeader-$other')));
    final target = paneRect('session-1').center;
    final gesture = await tester.startGesture(bar);
    await tester.pump(const Duration(milliseconds: 600));
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(Offset.lerp(bar, target, step / 8)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(paneRect(other).top, lessThan(paneRect('session-1').top));

    await openMenu(tester, other);
    await tester.tap(find.text('Move out of split'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('splitTab-session-1')), findsNothing);
    expect(find.byKey(ValueKey('splitPane-$other')), findsNothing);
    expect(tabContent('session-1'), findsOneWidget);
    expect(tabContent(other), findsOneWidget);
  });

  testWidgets('a split is reordered as one tab', (tester) async {
    await openTwoTabs(tester);
    final other = secondId(tester);
    await tester.tap(find.byKey(const ValueKey('tabBarAddButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Machine 2').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await splitViaMenu(tester, other);

    final split = find.byKey(const ValueKey('splitTab-session-1'));
    final third = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'sessionTabContent-',
              ) &&
              ![
                'session-1',
                other,
              ].any((id) => (w.key! as ValueKey<String>).value.endsWith(id)),
        )
        .first;
    expect(tester.getCenter(split).dx, lessThan(tester.getCenter(third).dx));

    final start = tester.getCenter(split);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(start + Offset(500 * step / 8, 0));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(split, findsOneWidget);
    expect(tester.getCenter(split).dx, greaterThan(tester.getCenter(third).dx));
  });

  testWidgets('with the keyboard up only the focused pane stays open, the '
      'other folded to its bar', (tester) async {
    await openTwoTabs(tester);
    final other = secondId(tester);
    await splitViaMenu(tester, other);

    final header = find.byKey(const ValueKey('splitHeader-session-1'));
    expect(header, findsOneWidget);
    expect(find.byKey(ValueKey('splitHeader-$other')), findsOneWidget);
    final pane = find.byKey(
      const ValueKey('splitPane-session-1'),
      skipOffstage: false,
    );
    final foldedSize = tester.getSize(pane);
    final openHeight = tester.getSize(find.byKey(ValueKey('splitPane-$other')));

    double slot(String id) =>
        tester.getSize(find.byKey(ValueKey('splitPaneSlot-$id'))).height;
    final openSlot = slot('session-1');

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 100));
    expect(slot('session-1'), inExclusiveRange(0, openSlot));
    expect(tester.getSize(pane), foldedSize);

    await tester.pump(const Duration(milliseconds: 300));
    expect(slot('session-1'), 0);
    expect(tester.getSize(pane), foldedSize);
    expect(header.hitTestable(), findsOneWidget);
    expect(
      tester.getSize(find.byKey(ValueKey('splitPane-$other'))).height,
      greaterThan(openHeight.height - 300),
    );

    await tester.tap(header);
    await tester.pump();
    expect(isActive(tester, 'session-1'), isTrue);
    expect(
      find.byKey(ValueKey('splitPane-$other')).hitTestable(),
      findsNothing,
    );
    expect(pane.hitTestable(), findsOneWidget);
  });

  testWidgets('a folded pane keeps its size when the panes trade places', (
    tester,
  ) async {
    await openTwoTabs(tester);
    final other = secondId(tester);
    await splitViaMenu(tester, other);

    final pane = find.byKey(
      const ValueKey('splitPane-session-1'),
      skipOffstage: false,
    );
    final openSize = tester.getSize(pane);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(pane), openSize);

    final bar = tester.getCenter(
      find.byKey(const ValueKey('splitHeader-session-1')),
    );
    final target = tester.getCenter(find.byKey(ValueKey('splitHeader-$other')));
    final gesture = await tester.startGesture(bar);
    await tester.pump(const Duration(milliseconds: 600));
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(Offset.lerp(bar, target, step / 8)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.getSize(pane), openSize);
  });
}
