import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/snippet.dart';
import 'package:termphin/services/storage/profile_storage.dart';
import 'package:termphin/services/storage/snippet_storage.dart';
import 'package:termphin/services/storage/ssh_key_storage.dart';
import 'package:termphin/services/storage/write_queue.dart';

import '../../support/fake_master_key_store.dart';
import '../../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WriteQueue', () {
    test(
      'runs actions one at a time, in the order they were handed over',
      () async {
        final queue = WriteQueue();
        final events = <String>[];

        Future<void> slow(String label, Duration delay) => queue.run(() async {
          events.add('$label:start');
          await Future<void>.delayed(delay);
          events.add('$label:end');
        });

        await Future.wait([
          slow('a', const Duration(milliseconds: 20)),
          slow('b', Duration.zero),
        ]);

        expect(events, ['a:start', 'a:end', 'b:start', 'b:end']);
      },
    );

    test(
      'an action that throws reaches its own caller and nobody else',
      () async {
        final queue = WriteQueue();

        final failed = queue.run<void>(() async => throw StateError('nope'));
        await expectLater(failed, throwsStateError);

        expect(await queue.run(() async => 'fine'), 'fine');
      },
    );
  });

  group('storage under concurrent mutation', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('profiles added at the same time all survive', () async {
      final storage = ProfileStorage(cipher: cipherFixture());
      await Future.wait([
        for (var i = 0; i < 5; i++)
          storage.addProfile(profileFixture(id: 'p$i', name: 'host $i')),
      ]);

      expect((await storage.loadProfiles()).length, 5);
    });

    test(
      'a delete racing an add does not resurrect the deleted profile',
      () async {
        final storage = ProfileStorage(cipher: cipherFixture());
        await storage.addProfile(profileFixture(id: 'gone'));

        await Future.wait([
          storage.deleteProfile('gone'),
          storage.addProfile(profileFixture(id: 'fresh')),
        ]);

        expect((await storage.loadProfiles()).map((profile) => profile.id), [
          'fresh',
        ]);
      },
    );

    test('snippets added at the same time all survive', () async {
      final storage = SnippetStorage();
      await Future.wait([
        for (var i = 0; i < 5; i++)
          storage.addSnippet(
            Snippet(
              id: 's$i',
              name: 'snippet $i',
              command: 'echo $i',
              createdAt: DateTime(2026),
            ),
          ),
      ]);

      expect((await storage.loadSnippets()).length, 5);
    });

    test('keys generated at the same time all survive', () async {
      final storage = SshKeyStorage(cipher: cipherFixture());
      await Future.wait([
        for (var i = 0; i < 3; i++)
          storage.generateEd25519('key $i', group: 'General'),
      ]);

      expect((await storage.loadKeys()).length, 3);
    });
  });
}
