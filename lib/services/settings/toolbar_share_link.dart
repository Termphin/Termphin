import 'dart:convert';
import 'dart:math' as math;

import 'toolbar_layout.dart';

/// `termphin://toolbar?d=...` - a toolbar layout carried whole in a link, so
/// a page of ready-made layouts needs no server and a link can be passed on
/// like any other.
///
/// The payload is base64url JSON: a version, a name, the grid's shape and
/// the keys as the app's own ids. The site's ready-made layouts use the
/// same format, so the two ends read and write one format.
///
/// A link is something somebody else hands you, so reading one is strict:
/// a key this build does not know, or a snippet - which names something on the
/// sender's phone and could run anything on the receiver's - is left out, and
/// the shape is clamped the way an import from a backup is.
const kToolbarLinkScheme = 'termphin';
const kToolbarLinkHost = 'toolbar';
const _version = 1;

/// Longer than any real layout - five pages of text keys - and short enough
/// that a link built to exhaust memory is turned away before it is decoded.
const _maxLinkLength = 16000;
const _maxNameLength = 40;

/// What a toolbar link holds once read: the layout, its name, and how many of
/// its keys had to be left out.
class ToolbarShare {
  const ToolbarShare({
    required this.name,
    required this.layout,
    this.droppedKeys = 0,
  });

  final String name;
  final ToolbarLayout layout;
  final int droppedKeys;
}

/// The link that carries [layout] under [name]. Trailing empty slots are left
/// out; the shape says how many there are.
String toolbarShareLink({required String name, required ToolbarLayout layout}) {
  final order = List<String>.of(layout.order);
  while (order.isNotEmpty && order.last.isEmpty) {
    order.removeLast();
  }
  final payload = jsonEncode({
    'v': _version,
    'n': name,
    'c': layout.columns,
    'r': layout.rows,
    'p': layout.pages,
    'o': order,
  });
  final data = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  return '$kToolbarLinkScheme://$kToolbarLinkHost?d=$data';
}

/// Whether [raw] is meant to be a toolbar link, readable or not - so a
/// mangled one is answered with a message rather than treated as an `ssh://`
/// link that failed to parse.
bool isToolbarShareLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  return uri != null &&
      uri.scheme.toLowerCase() == kToolbarLinkScheme &&
      uri.host.toLowerCase() == kToolbarLinkHost;
}

/// Reads a toolbar link, or returns null when it cannot be read or holds no
/// key this build has.
///
/// The shape is worked out first, so the keys can be laid into exactly the
/// slots it has, then padded with blanks rather than normalized: normalizing
/// a short order would fill the gaps from the default layout and add keys
/// the link never had, and would shift every key after a dropped duplicate
/// into the wrong slot. A key that appears twice keeps its first slot and
/// leaves the second blank instead.
ToolbarShare? parseToolbarShareLink(String raw) {
  if (raw.length > _maxLinkLength) return null;
  if (!isToolbarShareLink(raw)) return null;
  final data = Uri.tryParse(raw.trim())?.queryParameters['d'];
  if (data == null || data.isEmpty) return null;

  final Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(data))),
    );
    if (decoded is! Map<String, dynamic>) return null;
    json = decoded;
  } on FormatException {
    return null;
  }
  if (json['v'] != _version) return null;

  final rawOrder = json['o'];
  if (rawOrder is! List) return null;
  final columns = _int(json['c'], kToolbarColumns);
  final rows = _int(json['r'], kToolbarRows);
  final slotsPerPage = columns * rows;
  final pages = math.max(
    _int(json['p'], 1),
    (rawOrder.length / slotsPerPage).ceil(),
  );

  final shape = clampToolbarLayout(
    ToolbarLayout(order: const [], columns: columns, rows: rows, pages: pages),
  );

  var dropped = 0;
  final seen = <String>{};
  final order = List<String>.filled(shape.slotCount, '');
  for (var i = 0; i < rawOrder.length; i++) {
    final entry = rawOrder[i];
    final id = entry is String ? entry : '';
    if (id.isEmpty) continue;
    final usable =
        i < order.length &&
        !id.startsWith(kToolbarSnippetPrefix) &&
        toolbarActionForId(id) != null &&
        seen.add(id);
    if (usable) {
      order[i] = id;
    } else {
      dropped++;
    }
  }
  if (order.every((id) => id.isEmpty)) return null;

  final layout = shape.copyWith(order: order);

  final name = json['n'] is String ? (json['n'] as String).trim() : '';
  return ToolbarShare(
    name: name.length > _maxNameLength
        ? name.substring(0, _maxNameLength).trim()
        : name,
    layout: layout,
    droppedKeys: dropped,
  );
}

int _int(Object? value, int fallback) =>
    value is num ? value.toInt() : fallback;
