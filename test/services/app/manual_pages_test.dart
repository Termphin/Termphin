import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/app/manual_urls.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/utils/connection_error_text.dart';

const _docs = '../termphin-assets/landing/docs/src/content/docs';

File _source(ManualPage page) {
  if (page.path.isEmpty) return File('$_docs/index.mdx');
  final file = File('$_docs/${page.path}.mdx');
  return file.existsSync() ? file : File('$_docs/${page.path}/index.mdx');
}

/// The id the site gives a heading: github-slugger, which is what Astro uses.
String _slug(String heading) => heading
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}\p{Pc} -]', unicode: true), '')
    .replaceAll(' ', '-');

/// Checks the manual's pages and headings the app links to. The manual's
/// source lives with the website, outside the app's public repository, so
/// these skip where it is absent.
void main() {
  final missing = !Directory(_docs).existsSync();
  group(
    'manual pages',
    () {
      test('the slugger matches the ids the site renders', () {
        expect(
          _slug(
            "This server's key has changed. Remove the old one in Settings → "
            'Known hosts if that was expected.',
          ),
          'this-servers-key-has-changed-remove-the-old-one-in-settings--known-'
          'hosts-if-that-was-expected',
        );
      });

      for (final page in ManualPage.values) {
        test('${page.name} points at a page and heading that exist', () {
          final source = _source(page);
          expect(
            source.existsSync(),
            isTrue,
            reason: '${page.path} has no page',
          );
          final anchor = page.anchor;
          if (anchor == null) return;
          final ids = RegExp(r'^#{2,4} (.+)$', multiLine: true)
              .allMatches(source.readAsStringSync())
              .map((m) => _slug(m.group(1)!.trim()));
          expect(ids, contains(anchor));
        });
      }

      test(
        'every failure the troubleshooting page covers lands on its heading',
        () {
          for (final reason in SshFailureReason.values) {
            for (final method in AuthMethod.values) {
              final page = connectionErrorManualPage(reason, method);
              expect(page.path, 'help/troubleshooting', reason: reason.name);
              final generic =
                  reason == SshFailureReason.protocol ||
                  reason == SshFailureReason.unknown;
              expect(page.anchor == null, generic, reason: reason.name);
            }
          }
        },
      );

      test('a refused key and a refused password are different headings', () {
        expect(
          connectionErrorManualPage(
            SshFailureReason.authFailed,
            AuthMethod.privateKey,
          ),
          ManualPage.keyRefused,
        );
        expect(
          connectionErrorManualPage(
            SshFailureReason.authFailed,
            AuthMethod.password,
          ),
          ManualPage.wrongPassword,
        );
      });
    },
    skip: missing ? 'the manual source ($_docs) is not in this checkout' : null,
  );
}
