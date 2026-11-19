import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/platform/desktop_tray.dart';
import 'package:termphin/services/platform/tray_menu.dart';
import 'package:tray_kit/tray_kit.dart';

import '../../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t = AppLocale.en.buildSync();

  group('buildTrayMenu', () {
    List<TrayMenuEntry> build({
      List<DateTime?> lastConnected = const [],
      bool anonymize = false,
    }) => buildTrayMenu(
      t: t,
      connected: const [],
      profiles: [
        for (var i = 0; i < lastConnected.length; i++)
          profileFixture(
            id: 'p$i',
            name: 'machine $i',
            lastConnectedAt: lastConnected[i],
          ),
      ],
      anonymize: anonymize,
      onShow: () {},
      onOpenSession: (_) {},
      onNewSession: (_) {},
      onQuit: () {},
    );

    List<String> newSessionLabels(List<TrayMenuEntry> menu) => [
      for (final entry
          in menu
              .firstWhere((e) => e.label == t.window.trayNewSession)
              .children)
        entry.label,
    ];

    test('offers the machines used last, the most recent first', () {
      final now = DateTime(2026, 10, 3);
      final menu = build(
        lastConnected: [
          null,
          for (var day = 1; day <= 6; day++) now.subtract(Duration(days: day)),
        ],
      );

      expect(newSessionLabels(menu), [
        'machine 1',
        'machine 2',
        'machine 3',
        'machine 4',
        'machine 5',
      ]);
    });

    test('hides machine names when anonymized', () {
      final menu = build(lastConnected: [DateTime(2026)], anonymize: true);

      expect(newSessionLabels(menu).single, isNot('machine 0'));
    });

    test('has no new-session entry without machines', () {
      expect(
        build().map((e) => e.label),
        isNot(contains(t.window.trayNewSession)),
      );
    });
  });

  test('the menu reaches tray_kit as the same tree', () {
    var picked = 0;
    final items = TrayKitBackend.toTrayMenu([
      TrayMenuEntry(label: 'a', onSelected: () => picked++),
      const TrayMenuEntry.separator(),
      const TrayMenuEntry(
        label: 'sub',
        children: [TrayMenuEntry(label: 'b', enabled: false)],
      ),
    ]);

    final action = items[0] as TrayMenuAction;
    action.onSelected!();
    expect(action.label, 'a');
    expect(picked, 1);
    expect(items[1], isA<TrayMenuSeparator>());
    final submenu = items[2] as TraySubmenu;
    expect(submenu.label, 'sub');
    expect((submenu.items.single as TrayMenuAction).enabled, isFalse);
  });
}
