import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_keys_provider.dart';
import 'package:termphin/screens/onboarding_screen.dart';
import 'package:termphin/services/app/onboarding_service.dart';
import 'package:termphin/services/ssh/ssh_config_import.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

SshConfigCandidate _candidate(
  String alias, {
  String key = '/home/me/.ssh/id_ed25519',
  SshConfigProblem? problem,
}) => SshConfigCandidate(
  host: SshConfigHost(alias: alias, hostName: '$alias.example.com', port: 22),
  username: 'me',
  keyPath: problem == null ? key : null,
  keyPem: problem == null ? 'PEM of $key' : null,
  problem: problem,
);

void main() {
  const analyticsChannel = MethodChannel('posthog_flutter');
  final t = AppLocale.en.buildSync();
  late FakeProfileStorage profiles;
  late FakeSshKeyStorage keys;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, (call) async => null);
    profiles = FakeProfileStorage();
    keys = FakeSshKeyStorage();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, null);
  });

  Future<void> pump(
    WidgetTester tester, {
    List<SshConfigCandidate> found = const [],
    ValueChanged<OnboardingResult>? onComplete,
  }) async {
    final container = ProviderContainer.test(
      overrides: [
        profileStorageProvider.overrideWithValue(profiles),
        sshKeyStorageProvider.overrideWithValue(keys),
      ],
    );
    await pumpTestApp(
      tester,
      OnboardingScreen(
        onComplete: onComplete ?? (_) {},
        sshConfigLoader: (_) async => found,
      ),
      container: container,
    );
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('a panel with its steps down the side, not a carousel', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byKey(const ValueKey('desktopOnboarding')), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.text(t.onboarding.stepWelcome), findsOneWidget);
    expect(find.text(t.onboarding.stepServer), findsOneWidget);
    expect(find.text(t.onboarding.stepPrivacy), findsOneWidget);
    expect(find.text(t.onboarding.welcomeBodyDesktop), findsOneWidget);
    expect(find.text(t.onboarding.permissionsTitle), findsNothing);
  }, variant: _linux);

  testWidgets('the keyboard alone goes through it: Enter, 2, Enter, Enter', (
    tester,
  ) async {
    OnboardingResult? result;
    await pump(tester, onComplete: (r) => result = r);

    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text(t.onboarding.serverTitle), findsOneWidget);

    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text(t.onboarding.serverTitle), findsOneWidget);

    await press(tester, LogicalKeyboardKey.digit2);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text(t.analyticsConsent.title), findsOneWidget);

    await press(tester, LogicalKeyboardKey.enter);
    expect(result?.answer, ServerAnswer.notYet);
    expect(result?.target, isNull);
    expect(await OnboardingService.instance.isCompleted(), isTrue);
  }, variant: _linux);

  testWidgets('Esc goes back a step', (tester) async {
    await pump(tester);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text(t.onboarding.serverTitle), findsOneWidget);

    await press(tester, LogicalKeyboardKey.escape);

    expect(find.text(t.onboarding.welcomeTitle), findsOneWidget);
  }, variant: _linux);

  testWidgets('an address typed on the way opens the form filled in', (
    tester,
  ) async {
    OnboardingResult? result;
    await pump(tester, onComplete: (r) => result = r);
    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.digit1);

    final field = find.byKey(const ValueKey('onboardingTarget'));
    await tester.enterText(field, 'two words');
    await tester.tap(find.byKey(const ValueKey('onboardingContinue')));
    await tester.pumpAndSettle();
    expect(find.text(t.profiles.quickAddInvalid), findsOneWidget);

    await tester.enterText(field, 'ops@db.example.com:2200');
    await tester.tap(find.byKey(const ValueKey('onboardingContinue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboardingContinue')));
    await tester.pumpAndSettle();

    expect(result?.answer, ServerAnswer.hasServer);
    expect(result?.target?.host, 'db.example.com');
    expect(result?.target?.user, 'ops');
    expect(result?.target?.port, 2200);
  }, variant: _linux);

  testWidgets('hosts from ~/.ssh/config come in ticked, with one key for '
      'those that share it', (tester) async {
    OnboardingResult? result;
    await pump(
      tester,
      found: [
        _candidate('web'),
        _candidate('pi'),
        _candidate('old'),
        _candidate('locked', problem: SshConfigProblem.encryptedKey),
      ],
      onComplete: (r) => result = r,
    );
    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.digit1);

    expect(find.text(t.onboarding.sshConfigTitle), findsOneWidget);
    expect(
      find.textContaining(t.onboarding.sshConfigEncrypted),
      findsOneWidget,
    );
    final old = find.byKey(const ValueKey('sshConfigHost-old'));
    await tester.ensureVisible(old);
    await tester.tap(old);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('onboardingContinue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboardingContinue')));
    await tester.pumpAndSettle();

    expect(result?.imported, 2);
    expect(profiles.profiles.map((p) => p.name), ['web', 'pi']);
    expect(keys.keys, hasLength(1));
    for (final profile in profiles.profiles) {
      expect(profile.authMethod, AuthMethod.privateKey);
      expect(profile.sshKeyId, keys.keys.single.id);
      expect(profile.username, 'me');
    }
  }, variant: _linux);

  testWidgets('without a server nothing is imported', (tester) async {
    OnboardingResult? result;
    await pump(
      tester,
      found: [_candidate('web')],
      onComplete: (r) => result = r,
    );
    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.digit2);
    expect(find.text(t.onboarding.sshConfigTitle), findsNothing);
    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.enter);

    expect(result?.imported, 0);
    expect(profiles.profiles, isEmpty);
  }, variant: _linux);
}
