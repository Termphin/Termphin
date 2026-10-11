import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/snippet.dart';

void main() {
  Snippet build(String command) => Snippet(
    id: 'id',
    name: 'name',
    command: command,
    createdAt: DateTime(2026),
  );

  group('Snippet.placeholders', () {
    test('extracts distinct tokens in first-seen order', () {
      final snippet = build('cp {{src}} {{dest}} && chmod {{mode}} {{dest}}');
      expect(snippet.placeholders, ['src', 'dest', 'mode']);
    });

    test('empty when command has no placeholders', () {
      expect(build('docker ps').placeholders, isEmpty);
    });
  });

  group('Snippet.interpolate', () {
    test('substitutes provided values', () {
      final snippet = build('ssh {{user}}@{{host}}');
      expect(
        snippet.interpolate({'user': 'root', 'host': '10.0.0.1'}),
        'ssh root@10.0.0.1',
      );
    });

    test('missing values become empty string', () {
      final snippet = build('echo {{msg}}');
      expect(snippet.interpolate(const {}), 'echo ');
    });
  });

  group('json round-trip', () {
    test('encode/decode preserves fields', () {
      final snippet = Snippet(
        id: 'abc',
        name: 'restart nginx',
        command: 'sudo systemctl restart nginx',
        createdAt: DateTime(2026, 1, 1),
        group: 'ops',
      );
      final decoded = Snippet.decode(snippet.encode());
      expect(decoded.id, snippet.id);
      expect(decoded.name, snippet.name);
      expect(decoded.command, snippet.command);
      expect(decoded.group, snippet.group);
      expect(snippet.toJson().containsKey('tags'), isFalse);
    });

    test(
      'legacy tags read back as first tag as group and toJson never outputs tags',
      () {
        final legacy = Snippet.fromJson({
          'id': 's1',
          'name': 'restart',
          'command': 'reboot',
          'createdAt': DateTime(2026).toIso8601String(),
          'tags': ['prod', 'eu'],
        });
        expect(legacy.group, 'prod');
        expect(legacy.toJson().containsKey('tags'), isFalse);
        expect(legacy.toJson()['group'], 'prod');
      },
    );

    test('snippets stored before autoRun was dropped still decode', () {
      final decoded = Snippet.fromJson({
        'id': 'x',
        'name': 'n',
        'command': 'c',
        'createdAt': DateTime(2026).toIso8601String(),
        'autoRun': false,
      });
      expect(decoded.command, 'c');
    });

    test('argument defaults survive the round-trip', () {
      final snippet = Snippet(
        id: 'abc',
        name: 'deploy',
        command: 'deploy {{env}} --tag {{tag}}',
        createdAt: DateTime(2026, 1, 1),
        defaults: const {'env': 'staging'},
      );

      final decoded = Snippet.decode(snippet.encode());

      expect(decoded.defaults, {'env': 'staging'});
      expect(decoded.defaultFor('env'), 'staging');
      expect(decoded.defaultFor('tag'), '');
    });

    test('snippets stored before defaults existed decode with none', () {
      final decoded = Snippet.fromJson({
        'id': 'x',
        'name': 'n',
        'command': 'c {{host}}',
        'createdAt': DateTime(2026).toIso8601String(),
      });

      expect(decoded.defaults, isEmpty);
      expect(decoded.defaultFor('host'), '');
    });
  });

  group('placeholdersIn', () {
    test('reads tokens out of command text with no snippet around it', () {
      expect(Snippet.placeholdersIn('ssh {{host}} -p {{port}}'), [
        'host',
        'port',
      ]);
    });

    test('repeats collapse to one, in first-seen order', () {
      expect(Snippet.placeholdersIn('cp {{src}} {{dst}} && rm {{src}}'), [
        'src',
        'dst',
      ]);
    });
  });
}
