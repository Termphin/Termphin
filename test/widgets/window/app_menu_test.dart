import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/widgets/window/title_bar.dart';

import '../../support/test_app.dart';

List<String> _labels(WidgetTester tester) {
  final t = Translations.of(tester.element(find.byType(Scaffold)));
  return [for (final menu in appMenuModel(t, () => null)) menu.label];
}

AppMenu _menu(String label) => AppMenu(label, [
  [AppMenuItem(label: 'Do it', onSelected: () {})],
]);

void main() {
  testWidgets('a screen\'s menus stand between Termphin and View while it is '
      'there', (tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: ContextMenuScope(
          menus: (_) => [_menu('Files')],
          child: const SizedBox.shrink(),
        ),
      ),
    );
    expect(_labels(tester), ['Termphin', 'Files', 'View', 'Help']);

    await pumpTestApp(tester, const Scaffold(body: SizedBox.shrink()));
    expect(_labels(tester), ['Termphin', 'View', 'Help']);
  });

  testWidgets('an inactive scope publishes nothing', (tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: ContextMenuScope(
          active: false,
          menus: (_) => [_menu('Files')],
          child: const SizedBox.shrink(),
        ),
      ),
    );

    expect(_labels(tester), ['Termphin', 'View', 'Help']);
  });

  testWidgets('the bar is told when a screen\'s menus come and go', (
    tester,
  ) async {
    var notified = 0;
    void count() => notified++;
    ContextMenus.instance.addListener(count);
    addTearDown(() => ContextMenus.instance.removeListener(count));

    await pumpTestApp(
      tester,
      Scaffold(
        body: ContextMenuScope(
          menus: (_) => [_menu('Session')],
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    expect(notified, greaterThan(0));

    final before = notified;
    await pumpTestApp(tester, const Scaffold(body: SizedBox.shrink()));
    await tester.pump();
    expect(notified, greaterThan(before));
  });

  testWidgets('a section adds its menu only while it is the one on screen', (
    tester,
  ) async {
    Widget section({required bool onScreen}) => Scaffold(
      body: TickerMode(
        enabled: onScreen,
        child: SectionMenus(
          menus: (_) => [_menu('Snippets')],
          child: const SizedBox.shrink(),
        ),
      ),
    );

    await pumpTestApp(tester, section(onScreen: true));
    expect(_labels(tester), ['Termphin', 'Snippets', 'View', 'Help']);

    await pumpTestApp(tester, section(onScreen: false));
    expect(_labels(tester), ['Termphin', 'View', 'Help']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a phone gets no section menus', (tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: SectionMenus(
          menus: (_) => [_menu('Snippets')],
          child: const SizedBox.shrink(),
        ),
      ),
    );

    expect(_labels(tester), ['Termphin', 'View', 'Help']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  List<String> itemsOf(WidgetTester tester, String menu) {
    final t = Translations.of(tester.element(find.byType(Scaffold)));
    final found = appMenuModel(
      t,
      () => null,
    ).firstWhere((m) => m.label == menu);
    return [
      for (final group in found.groups)
        for (final item in group) item.label,
    ];
  }

  testWidgets('a Mac offers to check for updates', (tester) async {
    await pumpTestApp(tester, const Scaffold(body: SizedBox.shrink()));
    expect(itemsOf(tester, 'Termphin'), contains('Check for updates...'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('elsewhere nothing updates itself, so nothing offers to', (
    tester,
  ) async {
    await pumpTestApp(tester, const Scaffold(body: SizedBox.shrink()));
    expect(
      itemsOf(tester, 'Termphin'),
      isNot(contains('Check for updates...')),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
