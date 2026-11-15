import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/app/legal_updates_service.dart';
import 'package:termphin/services/app/onboarding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = LegalUpdatesService.instance;

  const source = '''
- id: 2026-10-01
  material: true
  summary: The first terms.
- id: 2026-11-15
  material: true
  summary: Pro arrived.
- id: 2026-12-01
  material: false
  summary: A typo fixed.
''';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.sourceOverride = source;
  });

  tearDown(() => service.sourceOverride = null);

  test('someone who used the app before is told about the newest material '
      'change, once', () async {
    expect((await service.pending())?.summary, 'Pro arrived.');

    await service.markSeen();

    expect(await service.pending(), isNull);
  });

  test('a later rewording alone is not announced', () async {
    SharedPreferences.setMockInitialValues({
      kLegalUpdateSeenPrefsKey: '2026-11-15',
    });

    expect(await service.pending(), isNull);
  });

  test(
    'someone new who finishes onboarding is not told about older changes',
    () async {
      await OnboardingService.instance.markCompleted();

      expect(await service.pending(), isNull);
    },
  );

  test('the bundled file reads, and its newest material change has a '
      'summary', () async {
    service.sourceOverride = null;

    final update = await service.pending();

    expect(update, isNotNull);
    expect(update!.summary, isNotEmpty);
  });
}
