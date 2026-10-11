import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/utils/link_metadata.dart';

const _base = 'https://example.com/some/page';

LinkMetadata parse(String html) =>
    LinkMetadata.parse(html, base: Uri.parse(_base));

void main() {
  group('Open Graph tags', () {
    test('reads title, description and image', () {
      final meta = parse('''
        <html><head>
          <meta property="og:title" content="The Title">
          <meta property="og:description" content="What the page is about">
          <meta property="og:image" content="https://cdn.example.com/a.png">
        </head></html>
      ''');

      expect(meta.title, 'The Title');
      expect(meta.description, 'What the page is about');
      expect(meta.imageUrl, 'https://cdn.example.com/a.png');
      expect(meta.isEmpty, isFalse);
    });

    test('reads them with content before property', () {
      final meta = parse('<meta content="Reversed" property="og:title">');
      expect(meta.title, 'Reversed');
    });

    test('accepts single quotes', () {
      final meta = parse("<meta property='og:title' content='Quoted'>");
      expect(meta.title, 'Quoted');
    });

    test('is case insensitive about the markup', () {
      final meta = parse('<META PROPERTY="OG:TITLE" CONTENT="Shouty">');
      expect(meta.title, 'Shouty');
    });

    test('tolerates extra attributes between the two it wants', () {
      final meta = parse(
        '<meta property="og:title" data-rh="true" content="Spaced out">',
      );
      expect(meta.title, 'Spaced out');
    });
  });

  group('falling back to plain HTML', () {
    test('uses <title> when there is no og:title', () {
      expect(parse('<title>Plain Title</title>').title, 'Plain Title');
    });

    test('uses meta description when there is no og:description', () {
      final meta = parse('<meta name="description" content="Plain desc">');
      expect(meta.description, 'Plain desc');
    });

    test('prefers Open Graph over the plain tags', () {
      final meta = parse('''
        <title>Plain</title>
        <meta name="description" content="Plain desc">
        <meta property="og:title" content="OG">
        <meta property="og:description" content="OG desc">
      ''');
      expect(meta.title, 'OG');
      expect(meta.description, 'OG desc');
    });

    test('handles a <title> carrying attributes', () {
      expect(parse('<title dir="ltr">Attr</title>').title, 'Attr');
    });
  });

  group('the image URL', () {
    test('turns a root-relative path into an absolute one', () {
      final meta = parse('<meta property="og:image" content="/img/hero.png">');
      expect(meta.imageUrl, 'https://example.com/img/hero.png');
    });

    test('drops the path of the page it came from', () {
      final meta = LinkMetadata.parse(
        '<meta property="og:image" content="/a.png">',
        base: Uri.parse('https://example.com/deep/nested/page.html'),
      );
      expect(meta.imageUrl, 'https://example.com/a.png');
    });

    test('leaves an absolute URL alone', () {
      final meta = parse(
        '<meta property="og:image" content="https://cdn.other.com/a.png">',
      );
      expect(meta.imageUrl, 'https://cdn.other.com/a.png');
    });

    test('gives a protocol-relative URL the page\'s own scheme', () {
      final meta = parse('<meta property="og:image" content="//cdn/a.png">');
      expect(meta.imageUrl, 'https://cdn/a.png');
    });

    test('resolves a path relative to the page it came from', () {
      final meta = parse('<meta property="og:image" content="hero.png">');
      expect(meta.imageUrl, 'https://example.com/some/hero.png');
    });

    test('keeps a relative path untouched with no base to resolve against', () {
      final meta = LinkMetadata.parse(
        '<meta property="og:image" content="/a.png">',
      );
      expect(meta.imageUrl, '/a.png');
    });

    test('keeps the port the page was served on', () {
      final meta = LinkMetadata.parse(
        '<meta property="og:image" content="/a.png">',
        base: Uri.parse('http://localhost:8080/page'),
      );
      expect(meta.imageUrl, 'http://localhost:8080/a.png');
    });
  });

  group('pages with nothing to show', () {
    test('reports empty for markup with no metadata', () {
      final meta = parse('<html><body>Just words</body></html>');
      expect(meta.isEmpty, isTrue);
      expect(meta.title, isNull);
    });

    test('reports empty for an empty document', () {
      expect(parse('').isEmpty, isTrue);
    });

    test('treats a blank value as absent rather than an empty preview', () {
      final meta = parse('<title>   </title>');
      expect(meta.title, isNull);
      expect(meta.isEmpty, isTrue);
    });

    test('trims the surrounding whitespace a page leaves in', () {
      expect(parse('<title>\n  Padded  \n</title>').title, 'Padded');
    });

    test('survives markup that never closes its tags', () {
      final meta = parse('<html><head><title>Cut off');
      expect(meta.isEmpty, isTrue);
    });
  });
}
