import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/providers/account_provider.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/push/notify_prefs_store.dart';
import 'package:termphin/widgets/settings/pro_devices_list.dart';
import 'package:termphin/widgets/ui/app_badge.dart';

import '../../support/test_app.dart';

class _Account extends AccountNotifier {
  @override
  AccountUser? build() =>
      const AccountUser(uid: 'u1', provider: AccountProvider.google);
}

void main() {
  test('a device is named and drawn by its platform and kind', () {
    final t = AppLocale.en.buildSync();
    const tablet = NotifyDestination(
      id: 't',
      platform: 'ios',
      kind: NotifyDeviceKind.tablet,
    );
    const unknown = NotifyDestination(id: 'u', platform: 'android');
    expect(notifyDeviceName(t, tablet), t.serversPanel.ipad);
    expect(notifyDeviceName(t, unknown), t.serversPanel.androidPhone);
    expect(notifyDeviceIcon(tablet), PhosphorIconsRegular.deviceTablet);
    expect(notifyDeviceIcon(unknown), PhosphorIconsRegular.deviceMobile);
    const named = NotifyDestination(
      id: 'n',
      platform: 'android',
      name: 'Work phone',
    );
    expect(notifyDeviceName(t, named), 'Work phone');
    expect(defaultNotifyDeviceName(t, named), t.serversPanel.androidPhone);
  });

  testWidgets('This device badge uses the accent tone', (tester) async {
    final container = ProviderContainer(
      overrides: [accountProvider.overrideWith(_Account.new)],
    );
    addTearDown(container.dispose);
    await pumpTestApp(
      tester,
      Scaffold(
        body: ProDevicesList(
          ownId: 'd1',
          devices: Stream.value(const [
            NotifyDestination(
              id: 'd1',
              platform: 'android',
              kind: NotifyDeviceKind.phone,
            ),
          ]),
        ),
      ),
      container: container,
    );
    await tester.pumpAndSettle();
    final badge = tester.widget<AppBadge>(find.byType(AppBadge));
    expect(badge.tone, BadgeTone.accent);
  });

  testWidgets('a device is renamed from its menu, and can go back', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [accountProvider.overrideWith(_Account.new)],
    );
    addTearDown(container.dispose);
    final renamed = <String?>[];
    final devices = StreamController<List<NotifyDestination>>.broadcast();
    addTearDown(devices.close);
    await pumpTestApp(
      tester,
      Scaffold(
        body: ProDevicesList(
          ownId: 'other',
          devices: devices.stream,
          rename: (device, name) async => renamed.add(name),
        ),
      ),
      container: container,
    );
    devices.add(const [NotifyDestination(id: 'd1', platform: 'android')]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Use the default name'), findsNothing);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Work phone');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(renamed, ['Work phone']);

    devices.add(const [
      NotifyDestination(id: 'd1', platform: 'android', name: 'Work phone'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Work phone'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use the default name'));
    await tester.pumpAndSettle();
    expect(renamed, ['Work phone', null]);
  });
}
