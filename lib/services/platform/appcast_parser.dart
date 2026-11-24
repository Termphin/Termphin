/// One update entry parsed from a Sparkle-compatible RSS appcast feed.
class AppcastEntry {
  const AppcastEntry({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.edSignature,
    this.length,
    this.os,
  });

  final String version;
  final String buildNumber;
  final Uri downloadUrl;
  final String edSignature;
  final int? length;
  final String? os;
}

final _itemPattern = RegExp(
  r'<item\b[^>]*>(.*?)</item>',
  dotAll: true,
  caseSensitive: false,
);

final _enclosurePattern = RegExp(
  r'<enclosure\b([^>]*)/?>',
  dotAll: true,
  caseSensitive: false,
);

final _attrPattern = RegExp(
  r'''([A-Za-z_:][A-Za-z0-9_.:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
);

/// Parses a Sparkle RSS appcast and returns the newest entry matching [os],
/// or `null` when no valid item exists.
AppcastEntry? parseAppcast(String xml, {String? os}) {
  final targetOs = os?.toLowerCase();
  AppcastEntry? best;

  for (final match in _itemPattern.allMatches(xml)) {
    final body = match.group(1) ?? '';
    final enclosureMatch = _enclosurePattern.firstMatch(body);
    if (enclosureMatch == null) continue;

    final attrs = _parseAttributes(enclosureMatch.group(1) ?? '');
    final entryOs = attrs['sparkle:os']?.toLowerCase();
    if (targetOs != null && entryOs != null && entryOs != targetOs) {
      continue;
    }

    final rawUrl = attrs['url'];
    final sig = attrs['sparkle:edSignature'];
    if (rawUrl == null || rawUrl.isEmpty || sig == null || sig.isEmpty) {
      continue;
    }
    final downloadUrl = Uri.tryParse(rawUrl);
    if (downloadUrl == null || !downloadUrl.hasScheme || !downloadUrl.hasAuthority) {
      continue;
    }

    final buildNumber =
        _tagValue(body, 'sparkle:version') ?? attrs['sparkle:version'] ?? '';
    final version =
        _tagValue(body, 'sparkle:shortVersionString') ??
        attrs['sparkle:shortVersionString'] ??
        buildNumber;
    if (buildNumber.isEmpty && version.isEmpty) continue;

    final length = int.tryParse(attrs['length'] ?? '');
    final candidate = AppcastEntry(
      version: version,
      buildNumber: buildNumber,
      downloadUrl: downloadUrl,
      edSignature: sig,
      length: length,
      os: entryOs,
    );

    if (best == null ||
        isNewerAppcastEntry(
          candidate,
          currentBuild: best.buildNumber,
          currentVersion: best.version,
        )) {
      best = candidate;
    }
  }

  return best;
}

/// True when [candidate] is newer than the currently running build.
bool isNewerAppcastEntry(
  AppcastEntry candidate, {
  required String currentBuild,
  required String currentVersion,
}) {
  final nextNum = int.tryParse(candidate.buildNumber.trim());
  final curNum = int.tryParse(currentBuild.trim());
  if (nextNum != null && curNum != null) {
    return nextNum > curNum;
  }
  return _compareSemver(candidate.version, currentVersion) > 0;
}

int _compareSemver(String a, String b) {
  List<int> parse(String value) => value
      .split('+')
      .first
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  final pa = parse(a);
  final pb = parse(b);
  final maxLen = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < maxLen; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

String? _tagValue(String body, String tagName) {
  final pattern = RegExp(
    '<${RegExp.escape(tagName)}\\b[^>]*>(.*?)</${RegExp.escape(tagName)}>',
    dotAll: true,
    caseSensitive: false,
  );
  final match = pattern.firstMatch(body);
  if (match == null) return null;
  return _unescapeXml((match.group(1) ?? '').trim());
}

Map<String, String> _parseAttributes(String raw) {
  final result = <String, String>{};
  for (final match in _attrPattern.allMatches(raw)) {
    final name = match.group(1);
    final value = match.group(2) ?? match.group(3);
    if (name != null && value != null) {
      result[name] = _unescapeXml(value);
    }
  }
  return result;
}

String _unescapeXml(String value) => value
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");
