import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/app/manual_urls.dart';

void main() {
  group('ManualUrls.isManual', () {
    test('keeps the manual itself in the web view', () {
      expect(isManual(ManualUrls.home), isTrue);
      expect(isManual('https://termphin.dev/docs'), isTrue);
      expect(isManual('https://termphin.dev/docs/'), isTrue);
      expect(
        isManual('https://termphin.dev/docs/sessions/remote-agent'),
        isTrue,
      );
      expect(
        isManual(
          'https://termphin.dev/docs/getting-started/first-connection#save',
        ),
        isTrue,
      );
    });

    test('follows the old manual host through its redirect', () {
      expect(
        isManual('https://manual.termphin.dev/connections/profiles'),
        isTrue,
      );
    });

    test('sends the rest of the web to a real browser', () {
      expect(isManual('https://termphin.dev/privacy'), isFalse);
      expect(isManual('https://termphin.dev/blog'), isFalse);
      expect(isManual('https://termphin.dev/'), isFalse);
      expect(isManual('https://github.com/Termphin'), isFalse);
    });

    test('a path that merely starts with ours is not ours', () {
      expect(isManual('https://termphin.dev/docsearch'), isFalse);
    });

    test('a host that merely starts with ours is not ours', () {
      expect(isManual('https://termphin.dev.example.com/docs'), isFalse);
      expect(isManual('https://manual.termphin.dev.evil.test/page'), isFalse);
    });

    test('the scheme has to match too', () {
      expect(isManual('http://termphin.dev/docs'), isFalse);
    });
  });
}

bool isManual(String url) => ManualUrls.isManual(Uri.parse(url));
