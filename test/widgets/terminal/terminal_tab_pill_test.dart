import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/providers/ssh_connection_provider.dart'
    show ConnectionStatus;
import 'package:termphin/widgets/terminal/notice_dot.dart';
import 'package:termphin/widgets/terminal/session_view.dart';
import 'package:termphin/widgets/terminal/terminal_tab_pill.dart';
import 'package:termphin/widgets/ui/app_dropdown.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  Future<void> pill(
    WidgetTester tester, {
    bool unread = false,
    List<DropdownItem<int>> menuItems = const [],
  }) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: Center(
          child: TerminalTabPill<int>(
            sessionId: 's',
            profile: profileFixture(),
            status: ConnectionStatus.connected,
            sessionName: null,
            displayName: 'devbox',
            mode: SessionViewMode.terminal,
            isActive: false,
            stretch: false,
            unread: unread,
            menuItems: menuItems,
            onTap: () {},
            onMenuAction: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double dotOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NoticeDot),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('a tab that notified shows a dot on its avatar', (tester) async {
    await pill(tester, unread: true);

    expect(dotOpacity(tester), 1);
  });

  testWidgets('a tab with nothing new shows none', (tester) async {
    await pill(tester, unread: false);

    expect(dotOpacity(tester), 0);
  });

  const rename = DropdownItem<int>(
    value: 1,
    intrinsicHeight: true,
    child: AppDropdownItem(key: ValueKey('rename'), label: 'Rename'),
  );

  testWidgets('the menu button is as tall as the tab and wider than its icon', (
    tester,
  ) async {
    await pill(tester, menuItems: [rename]);

    final tab = tester.getRect(
      find.byKey(const ValueKey('sessionTabContent-s')),
    );
    final button = tester.getRect(find.byKey(const ValueKey('tabMenu-s')));
    expect(button.height, tab.height - 2);
    expect(button.width, greaterThanOrEqualTo(kTabMenuButtonWidth));
    expect(button.right, tab.right - 1);
  });

  testWidgets('a tap at the top edge of the menu button opens the menu', (
    tester,
  ) async {
    await pill(tester, menuItems: [rename]);

    final button = tester.getRect(find.byKey(const ValueKey('tabMenu-s')));
    await tester.tapAt(button.topCenter + const Offset(0, 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('rename')), findsOneWidget);
  });

  testWidgets('a right click on the tab opens its menu', (tester) async {
    await pill(tester, menuItems: [rename]);

    await tester.tap(find.text('devbox'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('rename')), findsOneWidget);
  });
}
