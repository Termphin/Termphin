import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/pro/pro_hints.dart';
import 'package:termphin/services/pro/pro_service.dart';

import '../../support/fake_account_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime(2026, 11, 14, 9);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await proTipsSetting.load();
    AccountService.backendOverride = () => FakeAccountBackend();
    ProHints.instance.reset();
    ProService.instance.active.value = false;
    ProService.instance.settled.value = true;
  });

  tearDown(() {
    AccountService.backendOverride = null;
    ProHints.instance.reset();
    ProService.instance.active.value = false;
    ProService.instance.settled.value = false;
  });

  Future<bool?> markedShown(ProHint hint) async =>
      (await SharedPreferences.getInstance()).getBool(
        'pro_hint_shown_${hint.name}',
      );

  test(
    'a hint waiting for the Pro state becomes the card once it is known',
    () async {
      ProService.instance.settled.value = false;
      await ProHints.instance.offer(ProHint.longCommand);
      await pumpEventQueue();

      expect(ProHints.instance.current.value, isNull);

      await ProService.instance.refresh();
      await pumpEventQueue();

      expect(ProService.instance.settled.value, isTrue);
      expect(ProHints.instance.current.value, ProHint.longCommand);
    },
  );

  test('no card is ever shown to someone who has Pro', () async {
    ProService.instance.active.value = true;
    await ProHints.instance.offer(ProHint.longCommand);
    await pumpEventQueue();

    expect(ProHints.instance.current.value, isNull);
    expect(await markedShown(ProHint.longCommand), isNull);
  });

  test('a hint waiting when Pro turns on is dropped, not shown', () async {
    await withClock(Clock.fixed(start), () async {
      ProService.instance.settled.value = false;
      await ProHints.instance.offer(ProHint.longCommand);
    });
    ProService.instance.active.value = true;
    await pumpEventQueue();

    expect(ProHints.instance.current.value, isNull);
    expect(await markedShown(ProHint.longCommand), isNull);
  });

  test('Pro turning on takes the card off the screen', () async {
    await ProHints.instance.offer(ProHint.longCommand);
    expect(ProHints.instance.current.value, ProHint.longCommand);

    ProService.instance.active.value = true;

    expect(ProHints.instance.current.value, isNull);
  });

  test('with Pro tips off no hint is offered or shown', () async {
    await proTipsSetting.set(false);

    await ProHints.instance.offer(ProHint.longCommand);
    await pumpEventQueue();
    ProHints.instance.flush();

    expect(ProHints.instance.current.value, isNull);
    expect(await markedShown(ProHint.longCommand), isNull);
  });

  test('turning Pro tips off takes the card off the screen', () async {
    await ProHints.instance.offer(ProHint.longCommand);
    expect(ProHints.instance.current.value, ProHint.longCommand);

    await proTipsSetting.set(false);

    expect(ProHints.instance.current.value, isNull);
    expect(await markedShown(ProHint.longCommand), isNull);
  });

  test('a hint not dismissed is not marked shown', () async {
    await ProHints.instance.offer(ProHint.longCommand);
    await pumpEventQueue();

    expect(ProHints.instance.current.value, ProHint.longCommand);
    expect(await markedShown(ProHint.longCommand), isNull);
  });

  test('dismissing the card marks its hint shown, once ever', () async {
    await withClock(Clock.fixed(start), () async {
      await ProHints.instance.offer(ProHint.longCommand);
    });
    expect(ProHints.instance.current.value, ProHint.longCommand);

    ProHints.instance.dismiss();
    await pumpEventQueue();

    expect(ProHints.instance.current.value, isNull);
    expect(await markedShown(ProHint.longCommand), isTrue);

    await withClock(Clock.fixed(start.add(const Duration(days: 2))), () async {
      await ProHints.instance.offer(ProHint.longCommand);
    });
    await pumpEventQueue();

    expect(ProHints.instance.current.value, isNull);
  });

  test('the gap is kept across a restart of the app', () async {
    await withClock(Clock.fixed(start), () async {
      await ProHints.instance.offer(ProHint.longCommand);
    });
    expect(ProHints.instance.current.value, ProHint.longCommand);

    ProHints.instance.reset();
    await withClock(Clock.fixed(start.add(const Duration(hours: 2))), () async {
      await ProHints.instance.offer(ProHint.longCommand);
    });

    expect(ProHints.instance.current.value, isNull);
    expect(await markedShown(ProHint.longCommand), isNull);
  });

  test('forgetting shown hints clears the gap', () async {
    await withClock(Clock.fixed(start), () async {
      await ProHints.instance.offer(ProHint.longCommand);
    });
    ProHints.instance.dismiss();
    await pumpEventQueue();

    await ProHints.instance.forgetShown();
    await withClock(
      Clock.fixed(start.add(const Duration(minutes: 5))),
      () async {
        await ProHints.instance.offer(ProHint.longCommand);
      },
    );

    expect(ProHints.instance.current.value, ProHint.longCommand);
  });

  test(
    'showNow puts the card up regardless of once-ever and the gap',
    () async {
      ProHints.instance.showNow(ProHint.longCommand);

      expect(ProHints.instance.current.value, ProHint.longCommand);
    },
  );
}
