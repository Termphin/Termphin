import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/app.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/known_host.dart';
import 'package:termphin/services/app/identity_anonymizer.dart';
import 'package:termphin/services/settings/anonymize_setting.dart';
import 'package:termphin/services/ssh/ssh_prompts.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/ssh/host_key_dialog.dart';

HostKeyPromptRequest _request({
  HostKeyVerdict verdict = HostKeyVerdict.unknown,
  String host = 'example.com',
  int port = 22,
  String keyType = 'ssh-ed25519',
  String fingerprint = 'SHA256:AAAAfingerprintOfTheKeyPresented',
  String? pinnedFingerprint,
}) => HostKeyPromptRequest(
  host: host,
  port: port,
  keyType: keyType,
  fingerprint: fingerprint,
  verdict: verdict,
  pinnedFingerprint: pinnedFingerprint,
);

/// The prompt reaches for the root navigator rather than a context of its own,
/// so the app under test has to be the one carrying [navigatorKey].
Future<void> _pumpHost(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    ),
  );
}

void main() {
  final t = AppLocale.en.buildSync();

  testWidgets('with no navigator to ask through, the answer is no', (
    tester,
  ) async {
    expect(navigatorKey.currentContext, isNull);
    expect(await showHostKeyPrompt(_request()), isFalse);
  });

  group('an unknown host', () {
    testWidgets('shows the endpoint, fingerprint and key type', (tester) async {
      await _pumpHost(tester);
      unawaitedPrompt(_request());
      await tester.pumpAndSettle();

      expect(find.text(t.hostKey.newTitle), findsOneWidget);
      expect(find.text('example.com:22'), findsOneWidget);
      expect(
        find.text('SHA256:AAAAfingerprintOfTheKeyPresented'),
        findsOneWidget,
      );
      expect(
        find.text('${t.hostKey.keyTypeLabel}: ssh-ed25519'),
        findsOneWidget,
      );
      expect(find.text(t.hostKey.verifyHint), findsOneWidget);

      expect(find.text(t.hostKey.changedWarning), findsNothing);
      expect(find.text(t.hostKey.pinnedLabel), findsNothing);
    });

    testWidgets('anonymize hides the real host, not the port', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await anonymizeSetting.set(true);
      addTearDown(() => anonymizeSetting.set(false));
      await _pumpHost(tester);
      unawaitedPrompt(_request());
      await tester.pumpAndSettle();

      expect(
        find.text('${IdentityAnonymizer.host('example.com')}:22'),
        findsOneWidget,
      );
      expect(find.textContaining('example.com'), findsNothing);
    });

    testWidgets('accepting answers true', (tester) async {
      await _pumpHost(tester);
      final answer = showHostKeyPrompt(_request());
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.hostKey.accept));
      await tester.pumpAndSettle();
      expect(await answer, isTrue);
    });

    testWidgets('refusing answers false', (tester) async {
      await _pumpHost(tester);
      final answer = showHostKeyPrompt(_request());
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.hostKey.reject));
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
    });
  });

  group('a host key that changed', () {
    HostKeyPromptRequest changed() => _request(
      verdict: HostKeyVerdict.changed,
      fingerprint: 'SHA256:NEWkeyTheServerJustPresented',
      pinnedFingerprint: 'SHA256:OLDkeyThisDevicePinned',
    );

    testWidgets('shows both fingerprints and says what it could mean', (
      tester,
    ) async {
      await _pumpHost(tester);
      unawaitedPrompt(changed());
      await tester.pumpAndSettle();

      expect(find.text(t.hostKey.changedTitle), findsOneWidget);
      expect(find.text(t.hostKey.changedWarning), findsOneWidget);
      expect(find.text(t.hostKey.pinnedLabel), findsOneWidget);
      expect(find.text('SHA256:NEWkeyTheServerJustPresented'), findsOneWidget);
      expect(find.text('SHA256:OLDkeyThisDevicePinned'), findsOneWidget);
      expect(find.text(t.hostKey.newTitle), findsNothing);
    });

    testWidgets('offers the accept button under its own wording', (
      tester,
    ) async {
      await _pumpHost(tester);
      final answer = showHostKeyPrompt(changed());
      await tester.pumpAndSettle();

      expect(find.text(t.hostKey.accept), findsNothing);
      await tester.tap(find.text(t.hostKey.acceptChanged));
      await tester.pumpAndSettle();
      expect(await answer, isTrue);
    });

    testWidgets('refusing answers false', (tester) async {
      await _pumpHost(tester);
      final answer = showHostKeyPrompt(changed());
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.hostKey.reject));
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
    });
  });

  testWidgets('a tap outside decides nothing', (tester) async {
    await _pumpHost(tester);
    var answered = false;
    final answer = showHostKeyPrompt(_request(verdict: HostKeyVerdict.changed))
        .then((value) {
          answered = true;
          return value;
        });
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(answered, isFalse);
    expect(find.text(t.hostKey.changedTitle), findsOneWidget);

    await tester.tap(find.text(t.hostKey.reject));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });

  testWidgets('the fingerprint can be selected, so it can be compared', (
    tester,
  ) async {
    await _pumpHost(tester);
    unawaitedPrompt(_request());
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsWidgets);
  });
}

/// Raises the prompt without waiting for an answer, for the tests that only
/// look at what is on screen. The dialog is left for the test to dismiss.
void unawaitedPrompt(HostKeyPromptRequest request) {
  showHostKeyPrompt(request).ignore();
}
