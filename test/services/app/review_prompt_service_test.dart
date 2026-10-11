import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/app/review_prompt_service.dart';

class _FakeLauncher implements ReviewLauncher {
  bool available = true;
  bool throwOnRequest = false;
  int requests = 0;
  int storeOpens = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async {
    requests++;
    if (throwOnRequest) throw Exception('play unavailable');
  }

  @override
  bool get canOpenStoreListing => true;

  @override
  Future<void> openStoreListing() async => storeOpens++;
}

void main() {
  late DateTime now;
  late _FakeLauncher launcher;
  late ReviewPromptService service;

  ReviewPromptService build() =>
      ReviewPromptService.forTesting(launcher: launcher, now: () => now);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 1, 1);
    launcher = _FakeLauncher();
    service = build();
  });

  Future<void> connect(int times) async {
    for (var i = 0; i < times; i++) {
      await service.recordSuccessfulConnection();
    }
  }

  test('first connection seeds the clock, later ones do not move it', () async {
    await service.recordSuccessfulConnection();
    final seeded = DateTime(2026, 1, 1).millisecondsSinceEpoch;

    now = DateTime(2026, 1, 10);
    await service.recordSuccessfulConnection();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt(kReviewFirstConnectionAtPrefsKey), seeded);
    expect(preferences.getInt(kReviewSuccessfulConnectionsPrefsKey), 2);
  });

  test('stays quiet below five successful connections', () async {
    await connect(4);
    now = DateTime(2026, 2, 1);

    expect(await service.maybePrompt('0.4.1'), isFalse);
    expect(launcher.requests, 0);
  });

  test('stays quiet within three days of the first connection', () async {
    await connect(5);
    now = DateTime(2026, 1, 3, 23);

    expect(await service.maybePrompt('0.4.1'), isFalse);
    expect(launcher.requests, 0);
  });

  test('prompts once every gate is met', () async {
    await connect(5);
    now = DateTime(2026, 1, 5);

    expect(await service.maybePrompt('0.4.1'), isTrue);
    expect(launcher.requests, 1);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(kReviewLastPromptedVersionPrefsKey), '0.4.1');
    expect(
      preferences.getInt(kReviewPromptedAtPrefsKey),
      DateTime(2026, 1, 5).millisecondsSinceEpoch,
    );
  });

  test('stays quiet when Play has no review flow', () async {
    launcher.available = false;
    await connect(5);
    now = DateTime(2026, 1, 5);

    expect(await service.maybePrompt('0.4.1'), isFalse);
    expect(launcher.requests, 0);
  });

  test('a failed request burns no cooldown', () async {
    launcher.throwOnRequest = true;
    await connect(5);
    now = DateTime(2026, 1, 5);

    expect(await service.maybePrompt('0.4.1'), isFalse);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt(kReviewPromptedAtPrefsKey), isNull);

    launcher.throwOnRequest = false;
    expect(await service.maybePrompt('0.4.1'), isTrue);
  });

  test('does not ask again within the cooldown', () async {
    await connect(5);
    now = DateTime(2026, 1, 5);
    expect(await service.maybePrompt('0.4.1'), isTrue);

    now = DateTime(2026, 4, 1);
    expect(await service.maybePrompt('0.5.0'), isFalse);
    expect(launcher.requests, 1);
  });

  test('past the cooldown, only a new version asks again', () async {
    await connect(5);
    now = DateTime(2026, 1, 5);
    expect(await service.maybePrompt('0.4.1'), isTrue);

    now = DateTime(2026, 6, 1);
    expect(await service.maybePrompt('0.4.1'), isFalse);
    expect(await service.maybePrompt('0.5.0'), isTrue);
    expect(launcher.requests, 2);
  });

  test('the store listing has no gates', () async {
    await service.openStoreListing();
    expect(launcher.storeOpens, 1);
  });
}
