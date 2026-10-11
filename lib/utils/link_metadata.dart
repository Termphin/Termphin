/// What a link preview shows, read out of a page's own `<head>`.
///
/// Lifted out of `LinkPreviewPopup` so it can be tested against real pages'
/// markup: the widget around it does a network fetch on `initState`, which is
/// not something a test of "does this find the title" should have to stand up.
class LinkMetadata {
  const LinkMetadata({this.title, this.description, this.imageUrl});

  final String? title;
  final String? description;
  final String? imageUrl;

  bool get isEmpty => title == null && description == null && imageUrl == null;

  /// Reads Open Graph tags where a page has them and falls back to the plain
  /// `<title>` and `<meta name="description">` where it does not.
  ///
  /// [base] is what a root-relative `og:image` is resolved against - such a
  /// path is meaningless on its own, and left as-is it loads nothing.
  static LinkMetadata parse(String html, {Uri? base}) {
    final image = _og(html, 'image');
    return LinkMetadata(
      title: _clean(_og(html, 'title') ?? _tag(html, 'title')),
      description: _clean(
        _og(html, 'description') ?? _named(html, 'description'),
      ),
      imageUrl: _clean(_resolve(image, base)),
    );
  }

  /// Resolved against the page rather than pasted onto its host.
  ///
  /// Gluing `scheme://host` in front of anything starting with `/` mangles the
  /// two forms that also do: a protocol-relative `//cdn/a.png` came out as
  /// `https://example.com//cdn/a.png`, and a page served on a non-default port
  /// lost it. [Uri.resolve] covers those and plain relative paths besides.
  static String? _resolve(String? url, Uri? base) {
    final value = url?.trim();
    if (value == null || value.isEmpty || base == null) return value;
    try {
      return base.resolve(value).toString();
    } catch (_) {
      return value;
    }
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Both orderings, because `property` and `content` appear either way round
  /// and a page is under no obligation to pick the one we happened to write.
  static String? _og(String html, String property) =>
      _re(
        html,
        '<meta[^>]+property=["\']og:$property["\'][^>]+content=["\']([^"\']+)["\']',
      ) ??
      _re(
        html,
        '<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:$property["\']',
      );

  static String? _named(String html, String name) =>
      _re(
        html,
        '<meta[^>]+name=["\']$name["\'][^>]+content=["\']([^"\']+)["\']',
      ) ??
      _re(
        html,
        '<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']$name["\']',
      );

  static String? _tag(String html, String tag) =>
      _re(html, '<$tag[^>]*>([^<]+)</$tag>');

  static String? _re(String html, String pattern) =>
      RegExp(pattern, caseSensitive: false).firstMatch(html)?.group(1);
}
