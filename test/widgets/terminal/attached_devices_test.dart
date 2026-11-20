import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:termphin/providers/account_provider.dart';
import 'package:termphin/providers/anonymize_provider.dart';
import 'package:termphin/providers/live_presence_provider.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/realtime/presence_device.dart';
import 'package:termphin/services/realtime/presence_state.dart';
import 'package:termphin/widgets/terminal/attached_devices.dart';

import '../../support/test_app.dart';

class _FixedPresence extends LivePresenceNotifier {
  _FixedPresence(this.value);

  final Map<String, ServerPresence> value;

  @override
  Map<String, ServerPresence> build() => value;
}

class _Account extends AccountNotifier {
  _Account(this.user);

  final AccountUser? user;

  @override
  AccountUser? build() => user;
}

class _Anonymize extends AnonymizeNotifier {
  _Anonymize(this.value);

  final bool value;

  @override
  bool build() => value;
}

PresenceDevice _device(String id, PresenceDeviceKind kind, String name) =>
    PresenceDevice(id: id, kind: kind, name: name);

Map<String, ServerPresence> _presence(List<PresenceDevice> devices) => {
  'profile-a': ServerPresence(
    keyId: 'k',
    online: true,
    at: DateTime(2026),
    sessions: [
      PresenceSession(
        name: 'main',
        createdAt: DateTime(2026),
        clients: devices.length,
        devices: devices,
      ),
    ],
  ),
};

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<PresenceDevice> devices, {
    bool anonymize = false,
    String muxName = 'main',
    AccountUser? user,
  }) async {
    final container = ProviderContainer(
      overrides: [
        livePresenceProvider.overrideWith(
          () => _FixedPresence(_presence(devices)),
        ),
        thisDeviceIdProvider.overrideWith((ref) async => 'this-device'),
        anonymizeProvider.overrideWith(() => _Anonymize(anonymize)),
        accountProvider.overrideWith(() => _Account(user)),
      ],
    );
    addTearDown(container.dispose);
    await pumpTestApp(
      tester,
      Scaffold(
        body: Center(
          child: AttachedDevices(profileId: 'profile-a', muxName: muxName),
        ),
      ),
      container: container,
    );
    await tester.pump();
  }

  testWidgets('other devices show as circles, this one is left out', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, [
      _device('this-device', PresenceDeviceKind.phone, 'Android'),
      _device('pc', PresenceDeviceKind.desktop, 'Office PC'),
    ]);
    expect(find.bySemanticsLabel('Open on Office PC'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a circle names the device, not the signed-in account', (
    tester,
  ) async {
    await pump(
      tester,
      [_device('pc', PresenceDeviceKind.desktop, 'Office PC')],
      user: const AccountUser(
        uid: 'u',
        provider: AccountProvider.google,
        email: 'm@example.com',
      ),
    );
    expect(find.byIcon(PhosphorIconsRegular.desktop), findsOneWidget);
    expect(find.text('M'), findsNothing);
  });

  testWidgets('three circles at most, then a count', (tester) async {
    await pump(tester, [
      for (var i = 0; i < 5; i++)
        _device('d$i', PresenceDeviceKind.phone, 'Phone $i'),
    ]);
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('anonymized, a device is named by its kind only', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, [
      _device('pc', PresenceDeviceKind.desktop, 'secret-host'),
    ], anonymize: true);
    expect(find.bySemanticsLabel('Open on Computer'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('secret-host')), findsNothing);
    semantics.dispose();
  });

  testWidgets('nothing is drawn with no other device or another session', (
    tester,
  ) async {
    await pump(tester, [
      _device('this-device', PresenceDeviceKind.phone, 'Android'),
    ]);
    expect(find.byKey(const ValueKey('attachedDevices')), findsNothing);
    await pump(tester, [
      _device('pc', PresenceDeviceKind.desktop, 'Office PC'),
    ], muxName: 'other');
    expect(find.byKey(const ValueKey('attachedDevices')), findsNothing);
  });
}
