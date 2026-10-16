import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/app.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/terminal_overlay_provider.dart';
import 'package:termphin/services/platform/quick_actions_service.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/profiles/profile_avatar.dart';

import '../../support/fixtures.dart';
import '../../support/secure_storage_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/quick_actions');

  final service = QuickActionsService.instance;
  service.isReady = () => navigatorKey.currentContext?.mounted ?? false;
  service.onOpenProfile = (profile) {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    ProviderScope.containerOf(
      context,
    ).read(terminalOverlayProvider.notifier).openProfile(profile);
  };
  service.iconIds = ProfileAvatarData.icons.map((icon) => icon.id).toList();
  service.normalizeColorHex = (hex) => ProfileAvatarColor.forHex(hex).hex;

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('sorts shortcuts and consumes an action received at startup', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getLaunchAction') return null;
          return null;
        });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
      ),
    );
    final context = navigatorKey.currentContext!;
    final container = ProviderScope.containerOf(context);
    final subscription = container.listen(terminalOverlayProvider, (_, _) {});
    addTearDown(subscription.close);

    QuickActionsService.instance.init();
    await tester.pumpAndSettle();

    final launchCall = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('launch', 'profile-3'),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, launchCall, (_) {});
    await tester.pump();

    final profiles = [
      profileFixture(
        id: 'profile-1',
        name: 'One',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      profileFixture(
        id: 'profile-2',
        name: 'Two',
        createdAt: DateTime.utc(2026, 2, 1),
      ),
      profileFixture(
        id: 'profile-3',
        name: 'Three',
        createdAt: DateTime.utc(2026, 3, 1),
        iconName: null,
        colorHex: null,
      ),
      profileFixture(
        id: 'profile-4',
        name: 'Four',
        createdAt: DateTime.utc(2026, 4, 1),
        lastConnectedAt: DateTime.utc(2026, 6, 1),
      ),
      profileFixture(
        id: 'profile-5',
        name: 'Five',
        createdAt: DateTime.utc(2026, 5, 1),
      ),
    ];

    QuickActionsService.instance.update(profiles);
    await tester.pumpAndSettle();

    final shortcutCall = calls.singleWhere(
      (call) => call.method == 'setShortcutItems',
    );
    final items = shortcutCall.arguments as List<Object?>;
    expect(items.map((item) => (item as Map<Object?, Object?>)['type']), [
      'profile-4',
      'profile-5',
      'profile-3',
      'profile-2',
    ]);
    expect((items[2] as Map<Object?, Object?>)['icon'], 'qa_desktop_4da3ff');

    final session = container.read(terminalOverlayProvider);
    expect(session?.$2.id, 'profile-3');
    expect(session?.$1, isNotEmpty);
  });

  testWidgets('a shortcut picks up the session its machine left running', (
    tester,
  ) async {
    final machine = profileFixture(id: 'profile-9', name: 'Nine');
    SharedPreferences.setMockInitialValues({
      'ssh_profiles': SshProfile.encodeList([machine]),
      'session_tabs': [
        jsonEncode(
          SessionTab(
            tabId: 'waiting-tab',
            profileId: 'profile-9',
            muxName: 'termphin_waiting',
            lastSeen: DateTime.utc(2026, 1, 1),
          ).toJson(),
        ),
      ],
    });
    mockSecureStorage();
    await tester.runAsync(SshSessionManager.instance.init);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
      ),
    );
    final container = ProviderScope.containerOf(navigatorKey.currentContext!);
    final subscription = container.listen(terminalOverlayProvider, (_, _) {});
    addTearDown(subscription.close);

    QuickActionsService.instance.init();
    QuickActionsService.instance.update([machine]);
    await tester.pumpAndSettle();

    final launchCall = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('launch', 'profile-9'),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, launchCall, (_) {});
    await tester.pump();

    expect(container.read(terminalOverlayProvider)?.$1, 'waiting-tab');
  });

  testWidgets('the same machines are not handed to the system twice', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    final machines = [
      profileFixture(id: 'same-1', name: 'Same one'),
      profileFixture(id: 'same-2', name: 'Same two'),
    ];

    QuickActionsService.instance.update(machines);
    QuickActionsService.instance.update(List.of(machines));
    await tester.pump();
    expect(calls.where((m) => m == 'setShortcutItems'), hasLength(1));

    QuickActionsService.instance.update([
      machines.first.copyWith(name: 'Renamed'),
      machines.last,
    ]);
    await tester.pump();
    expect(calls.where((m) => m == 'setShortcutItems'), hasLength(2));
  });

  testWidgets('a system that refuses the shortcuts is reported once', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setShortcutItems') {
            throw PlatformException(code: 'channel-error');
          }
          return null;
        });
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    QuickActionsService.instance.update([
      profileFixture(id: 'refused-1', name: 'Refused'),
    ]);
    await tester.pump();
    QuickActionsService.instance.update([
      profileFixture(id: 'refused-2', name: 'Refused again'),
    ]);
    await tester.pump();

    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<PlatformException>());
  });

  testWidgets('the open-profile hook is called with the matching profile', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
      ),
    );

    final opened = <SshProfile>[];
    final previousHook = QuickActionsService.instance.onOpenProfile;
    QuickActionsService.instance.onOpenProfile = opened.add;
    addTearDown(
      () => QuickActionsService.instance.onOpenProfile = previousHook,
    );

    final profile = profileFixture(id: 'hooked-1', name: 'Hooked');
    QuickActionsService.instance.update([profile]);
    await tester.pump();

    final launchCall = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('launch', 'hooked-1'),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, launchCall, (_) {});
    await tester.pump();

    expect(opened.map((p) => p.id), ['hooked-1']);
  });
}
