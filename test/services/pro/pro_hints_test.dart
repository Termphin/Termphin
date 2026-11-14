import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/pro/pro_hints.dart';
import 'package:termphin/services/pro/pro_service.dart';

import '../../support/fake_account_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ProHint> shown;
  late bool answer;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountService.backendOverride = () => FakeAccountBackend();
    ProHints.instance.reset();
    ProService.instance.active.value = false;
    ProService.instance.settled.value = true;
    shown = [];
    answer = true;
    ProHints.instance.present = (hint) async {
      shown.add(hint);
      return answer;
    };
  });

  tearDown(() {
    AccountService.backendOverride = null;
    ProHints.instance.present = null;
    ProHints.instance.reset();
    ProService.instance.active.value = false;
    ProService.instance.settled.value = false;
  });

  Future<bool?> markedShown(ProHint hint) async =>
      (await SharedPreferences.getInstance()).getBool(
        'pro_hint_shown_${hint.name}',
      );

  test(
    'a hint the app could not show stays pending and is not marked shown',
    () async {
      answer = false;
      await ProHints.instance.offer(ProHint.longCommand);
      await pumpEventQueue();

      expect(shown, [ProHint.longCommand]);
      expect(await markedShown(ProHint.longCommand), isNull);

      answer = true;
      ProHints.instance.flush();
      await pumpEventQueue();

      expect(shown, [ProHint.longCommand, ProHint.longCommand]);
      expect(await markedShown(ProHint.longCommand), isTrue);
    },
  );

  test('a hint offered before the Pro state is known waits for it', () async {
    ProService.instance.settled.value = false;
    await ProHints.instance.offer(ProHint.machines);
    await pumpEventQueue();

    expect(shown, isEmpty);

    await ProService.instance.refresh();
    await pumpEventQueue();

    expect(ProService.instance.settled.value, isTrue);
    expect(shown, [ProHint.machines]);
    expect(await markedShown(ProHint.machines), isTrue);
  });

  test('a hint is never shown to someone who has Pro', () async {
    ProService.instance.active.value = true;
    await ProHints.instance.offer(ProHint.longCommand);
    await pumpEventQueue();

    expect(shown, isEmpty);
    expect(await markedShown(ProHint.longCommand), isNull);
  });

  test('a hint waiting when Pro turns on is dropped, not shown', () async {
    ProHints.instance.present = null;
    await ProHints.instance.offer(ProHint.droppedSession);
    await pumpEventQueue();

    ProService.instance.active.value = true;
    ProHints.instance.present = (hint) async {
      shown.add(hint);
      return true;
    };
    ProHints.instance.flush();
    await pumpEventQueue();

    expect(shown, isEmpty);
    expect(await markedShown(ProHint.droppedSession), isNull);
  });
}
