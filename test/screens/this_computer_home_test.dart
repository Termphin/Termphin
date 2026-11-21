import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_keys_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/screens/home_screen.dart';
import 'package:termphin/screens/terminal/terminal_screen.dart';
import 'package:termphin/services/realtime/presence_state.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/desktop_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/services/storage/group_storage.dart';
import 'package:termphin/services/terminal/local_agent_service.dart';
import 'package:termphin/services/terminal/local_agent_transport.dart';
import 'package:termphin/widgets/settings/terminal_controls_settings_section.dart';
import 'package:termphin/widgets/terminal/tab_menu_parts.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/secure_storage_channel.dart';
import '../support/ssh_fakes.dart';
import '../support/test_app.dart';

class _StubLocalAgentService extends LocalAgentService {
  _StubLocalAgentService({this.initialSessions = const []})
    : super(
        operatingSystem: 'Linux',
        architecture: 'x86_64',
        homeDirectory: '/tmp/home',
      );

  List<RemoteMuxSession> initialSessions;
  List<PresenceSession>? reported;
  int listCalls = 0;

  @override
  Future<String> ensureInstalled() async =>
      '/home/alice/.local/lib/termphin/termphin-agent';

  @override
  Future<List<RemoteMuxSession>> list() async {
    listCalls++;
    if (reported != null) presence.value = reported;
    return initialSessions;
  }
}

class _StubSink implements IOSink {
  final Completer<void> _done = Completer<void>();

  @override
  void add(List<int> data) {}

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubProcess implements Process {
  // ignore: close_sinks - fake in-memory sink closed in tests
  final _StubSink fakeStdin = _StubSink();
  final StreamController<List<int>> stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> stderrController =
      StreamController<List<int>>();
  final Completer<int> exitCompleter = Completer<int>();

  @override
  IOSink get stdin => fakeStdin;

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  Future<int> get exitCode => exitCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!exitCompleter.isCompleted) {
      unawaited(stdoutController.close());
      unawaited(stderrController.close());
      exitCompleter.complete(0);
    }
    return true;
  }

  @override
  int get pid => 2002;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    PackageInfo.setMockInitialValues(
      appName: 'Termphin',
      packageName: 'termphin',
      version: '1.12.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await loadAppSettings();
  });

  void setDesktopPlatform(TargetPlatform? platform) {
    debugDefaultTargetPlatformOverride = platform;
  }

  Future<ProviderContainer> pumpHome(
    WidgetTester tester, {
    required bool localSupported,
    List<SshProfile> profiles = const [],
    SshSessionManager? manager,
  }) async {
    final fakeProfiles = FakeProfileStorage(profiles);
    final fakeGroups = FakeGroupStorage(
      initialGroups: const [ProfileGroup(name: GroupStorage.defaultGroup)],
      profilesStorage: fakeProfiles,
    );
    final container = ProviderContainer.test(
      overrides: [
        profileStorageProvider.overrideWithValue(fakeProfiles),
        groupStorageProvider.overrideWithValue(fakeGroups),
        sshKeyStorageProvider.overrideWithValue(FakeSshKeyStorage()),
        localSessionsSupportedProvider.overrideWith(
          (ref) async => localSupported,
        ),
        if (manager != null)
          sshSessionManagerProvider.overrideWithValue(manager),
      ],
    );
    container.read(profilesProvider);
    await container.read(profilesProvider.notifier).loadProfiles();
    await container.read(profileGroupsProvider.notifier).loadGroups();
    await pumpTestApp(tester, const HomeScreen(), container: container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    return container;
  }

  testWidgets(
    'pinned card shows on desktop when bundle >= 0.21.0 and setting is on',
    (tester) async {
      setDesktopPlatform(TargetPlatform.linux);
      try {
        final t = AppLocale.en.buildSync();
        final localService = _StubLocalAgentService();
        final sshBackend = FakeSshBackend();
        final manager = SshSessionManager.test(
          remoteAgentService: FakeRemoteAgentService(sshBackend),
          serviceFactory: sshBackend.createService,
          localAgentService: localService,
        );
        addTearDown(manager.dispose);

        await pumpHome(
          tester,
          localSupported: true,
          profiles: [profileFixture()],
          manager: manager,
        );

        expect(find.byKey(const ValueKey('thisComputerCard')), findsOneWidget);
        expect(find.text(t.profiles.thisComputer), findsOneWidget);

        final thisCard = tester.getTopLeft(
          find.byKey(const ValueKey('thisComputerCard')),
        );
        final sshCard = tester.getTopLeft(find.text('Production'));
        expect(thisCard.dy, lessThan(sshCard.dy));

        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('thisComputerCard')),
            matching: find.byTooltip(t.profiles.moreActions),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(t.profiles.hideThisComputer), findsOneWidget);
        expect(find.text(t.common.edit), findsNothing);
        expect(find.text(t.common.delete), findsNothing);

        await tester.tap(find.text(t.profiles.hideThisComputer));
        await tester.pumpAndSettle();

        expect(showThisComputerSetting.value, isFalse);
        expect(find.byKey(const ValueKey('thisComputerCard')), findsNothing);
      } finally {
        setDesktopPlatform(null);
      }
    },
  );

  testWidgets(
    'pinned card is hidden on non-desktop platforms and when bundle < 0.21.0',
    (tester) async {
      try {
        setDesktopPlatform(TargetPlatform.android);
        await pumpHome(tester, localSupported: true);
        expect(find.byKey(const ValueKey('thisComputerCard')), findsNothing);

        setDesktopPlatform(TargetPlatform.linux);
        await pumpHome(tester, localSupported: false);
        expect(find.byKey(const ValueKey('thisComputerCard')), findsNothing);
      } finally {
        setDesktopPlatform(null);
      }
    },
  );

  testWidgets(
    'polls local sessions on show and every 5s and adopts new names',
    (tester) async {
      setDesktopPlatform(TargetPlatform.linux);
      try {
        final localService = _StubLocalAgentService(
          initialSessions: [
            RemoteMuxSession.fromMap({
              'name': 'from-phone',
              'windows': 1,
              'createdAt': 1700000000,
              'attached': false,
              'multiplexer': 'termphin',
            }),
          ],
        );
        final sshBackend = FakeSshBackend();
        final manager = SshSessionManager.test(
          remoteAgentService: FakeRemoteAgentService(sshBackend),
          serviceFactory: sshBackend.createService,
          localAgentService: localService,
        );
        addTearDown(manager.dispose);

        await pumpHome(tester, localSupported: true, manager: manager);

        expect(localService.listCalls, greaterThanOrEqualTo(1));
        expect(find.text('from-phone'), findsOneWidget);

        localService.initialSessions = [
          ...localService.initialSessions,
          RemoteMuxSession.fromMap({
            'name': 'second-phone',
            'windows': 1,
            'createdAt': 1700000010,
            'attached': false,
            'multiplexer': 'termphin',
          }),
        ];

        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        expect(find.text('second-phone'), findsOneWidget);
      } finally {
        setDesktopPlatform(null);
      }
    },
  );

  testWidgets('a local session row shows what it is doing, without a backend', (
    tester,
  ) async {
    setDesktopPlatform(TargetPlatform.linux);
    try {
      final localService =
          _StubLocalAgentService(
              initialSessions: [
                RemoteMuxSession.fromMap({
                  'name': 'from-phone',
                  'windows': 1,
                  'createdAt': 1700000000,
                  'attached': true,
                  'multiplexer': 'termphin',
                }),
              ],
            )
            ..reported = [
              PresenceSession(
                name: 'from-phone',
                createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
                clients: 1,
                activity: const SessionActivity(
                  state: SessionActivityState.working,
                  command: 'npm run build',
                ),
              ),
            ];
      final sshBackend = FakeSshBackend();
      final manager = SshSessionManager.test(
        remoteAgentService: FakeRemoteAgentService(sshBackend),
        serviceFactory: sshBackend.createService,
        localAgentService: localService,
      );
      addTearDown(manager.dispose);

      await pumpHome(tester, localSupported: true, manager: manager);
      await tester.pump();

      expect(find.textContaining('npm run build'), findsOneWidget);
    } finally {
      setDesktopPlatform(null);
    }
  });

  testWidgets('desktop settings switch brings back hidden This computer card', (
    tester,
  ) async {
    setDesktopPlatform(TargetPlatform.linux);
    try {
      await showThisComputerSetting.set(false);
      final container = ProviderContainer.test(
        overrides: [
          localSessionsSupportedProvider.overrideWith((ref) async => true),
        ],
      );
      await pumpTestApp(
        tester,
        const Scaffold(
          body: SingleChildScrollView(
            child: TerminalControlsSettingsSection(appVersion: '1.12.0'),
          ),
        ),
        container: container,
      );
      await tester.pumpAndSettle();

      final finder = find.byKey(const ValueKey('showThisComputerSwitch'));
      expect(finder, findsOneWidget);
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(showThisComputerSetting.value, isTrue);
    } finally {
      setDesktopPlatform(null);
    }
  });

  testWidgets('local tab hides Terminal/Files switch, tunnels and upload', (
    tester,
  ) async {
    setDesktopPlatform(TargetPlatform.linux);
    try {
      final t = AppLocale.en.buildSync();
      final localService = _StubLocalAgentService();
      final sshBackend = FakeSshBackend();
      final manager = SshSessionManager.test(
        remoteAgentService: FakeRemoteAgentService(sshBackend),
        serviceFactory: sshBackend.createService,
        localAgentService: localService,
        localTransportFactory: () => LocalAgentTransport(
          startProcess: (executable, arguments, _) async {
            final proc = _StubProcess();
            unawaited(
              Future<void>.microtask(() {
                proc.stdoutController.add(
                  utf8.encode(
                    '\x1b]5384;termphin-master;0.21.0\x07'
                    '\x1b]5380;termphin-replay-end\x07',
                  ),
                );
              }),
            );
            return proc;
          },
        ),
      );
      addTearDown(manager.dispose);

      final localProfile = localComputerProfile(name: t.profiles.thisComputer);
      final container = ProviderContainer.test(
        overrides: [
          sshSessionManagerProvider.overrideWithValue(manager),
          profileStorageProvider.overrideWithValue(
            FakeProfileStorage(const []),
          ),
        ],
      );
      await pumpTestApp(
        tester,
        TerminalScreen(
          initialSessionId: 'local-tab',
          initialProfile: localProfile,
        ),
        container: container,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('viewModeBadge-local-tab')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('tabMenu-local-tab')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ViewModeSegments), findsNothing);
      expect(find.text(t.portForwarding.manageTunnels), findsNothing);
      expect(find.text(t.session.rename), findsOneWidget);
    } finally {
      setDesktopPlatform(null);
    }
  });
}
