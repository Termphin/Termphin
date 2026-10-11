import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/widgets/ui/large_title_scaffold.dart';
import 'package:termphin/widgets/window/page_bar.dart';

import '../../support/test_app.dart';

Widget _page() => LargeTitleScaffold(
  title: 'Machines',
  actions: [
    IconButton(
      tooltip: 'Runs',
      onPressed: () {},
      icon: const Icon(Icons.play_arrow),
    ),
  ],
  bodyBuilder: (context, controller, gutter) => ListView(
    controller: controller,
    children: const [Text('row')],
  ),
);

void main() {
  testWidgets('a desktop page has no bar of its own and hands the title bar '
      'its title and actions', (tester) async {
    await pumpTestApp(tester, _page());
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('Runs'), findsNothing);
    final page = DesktopPageBar.instance.current;
    expect(page?.title, 'Machines');
    expect(page?.actions, hasLength(1));

    await pumpTestApp(tester, const Scaffold(body: SizedBox.shrink()));
    await tester.pump();
    expect(DesktopPageBar.instance.current, isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('a phone keeps its app bar and publishes nothing', (
    tester,
  ) async {
    await pumpTestApp(tester, _page());
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byTooltip('Runs'), findsOneWidget);
    expect(DesktopPageBar.instance.current, isNull);
  });
}
