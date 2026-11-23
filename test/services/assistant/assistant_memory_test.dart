import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/assistant/assistant_memory.dart';

import '../../support/secure_storage_channel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    mockSecureStorage();
  });

  test('keeps notes per server, sealed, across a restart', () async {
    final store = AssistantMemoryStore();
    expect(await store.add('a', 'App is shop-api.'), isTrue);
    expect(await store.add('a', 'app is SHOP-API.'), isFalse);
    expect(await store.add('b', 'Postgres in docker container db.'), isTrue);
    final raw = (await SharedPreferences.getInstance()).getString(
      'assistant_memory',
    );
    expect(raw, isNot(contains('shop-api')));
    store.forgetCache();
    expect(await store.notesFor('a'), ['App is shop-api.']);
    expect((await store.all()).keys, unorderedEquals(['a', 'b']));
  });

  test('keeps the newest notes and trims long ones', () async {
    final store = AssistantMemoryStore();
    for (var i = 0; i < AssistantMemoryStore.maxNotes + 5; i++) {
      await store.add('a', 'note $i');
    }
    final notes = await store.notesFor('a');
    expect(notes, hasLength(AssistantMemoryStore.maxNotes));
    expect(notes.first, 'note 5');
    await store.add('b', 'x' * 500);
    expect(
      (await store.notesFor('b')).single,
      hasLength(AssistantMemoryStore.maxLength),
    );
  });

  test('forgets a note, a server, everything', () async {
    final store = AssistantMemoryStore();
    await store.add('a', 'one');
    await store.add('a', 'two');
    await store.add('b', 'three');
    await store.remove('a', 'one');
    expect(await store.notesFor('a'), ['two']);
    await store.forget('a');
    expect(await store.notesFor('a'), isEmpty);
    await store.forgetAll();
    expect(await store.all(), isEmpty);
  });
}
