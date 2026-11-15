import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/providers/ssh_connection_provider.dart'
    show ConnectionStatus;
import 'package:termphin/widgets/terminal/notice_dot.dart';
import 'package:termphin/widgets/terminal/session_view.dart';
import 'package:termphin/widgets/terminal/terminal_tab_pill.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  Future<void> pill(WidgetTester tester, {required bool unread}) async {
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
            menuItems: const [],
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
}
