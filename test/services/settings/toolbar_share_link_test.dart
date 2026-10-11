import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/settings/toolbar_layout.dart';
import 'package:termphin/services/settings/toolbar_share_link.dart';

String _link(Map<String, Object?> payload) =>
    'termphin://toolbar?d=${base64Url.encode(utf8.encode(jsonEncode(payload)))}';

void main() {
  final compact = toolbarCustomActionId(text: '/compact', appendEnter: true);

  test('a layout survives the trip through a link', () {
    final layout = ToolbarLayout(
      order: ['esc', 'combo:c:c', compact, '', 'arrow_up', 'arrow_down'],
      columns: 6,
      rows: 1,
      pages: 1,
    );

    final share = parseToolbarShareLink(
      toolbarShareLink(name: 'Claude Code', layout: layout),
    )!;

    expect(share.name, 'Claude Code');
    expect(share.layout.columns, 6);
    expect(share.layout.rows, 1);
    expect(share.layout.pages, 1);
    expect(share.layout.order, layout.order);
    expect(share.droppedKeys, 0);
  });

  test('every page comes along, empty slots included', () {
    final share = parseToolbarShareLink(
      toolbarShareLink(name: 'Default', layout: ToolbarLayout.defaults),
    )!;

    expect(share.layout, ToolbarLayout.defaults);
  });

  test('a snippet or a key this build lacks is left out and counted', () {
    final share = parseToolbarShareLink(
      _link({
        'v': 1,
        'n': 'Mixed',
        'c': 5,
        'r': 1,
        'o': ['esc', 'snippet:rm-everything', 'no_such_key', 'tab'],
      }),
    )!;

    expect(share.layout.order.take(4), ['esc', '', '', 'tab']);
    expect(share.droppedKeys, 2);
  });

  test('a short or repeating list keeps every key where it was', () {
    final share = parseToolbarShareLink(
      _link({
        'v': 1,
        'n': 'Short',
        'c': 5,
        'r': 2,
        'o': ['esc', 'tab', 'esc', 'cr'],
      }),
    )!;

    expect(share.layout.order, ['esc', 'tab', '', 'cr', ...List.filled(6, '')]);
    expect(share.droppedKeys, 1);
  });

  test('the shape is clamped the way an import is', () {
    final share = parseToolbarShareLink(
      _link({
        'v': 1,
        'n': 'Huge',
        'c': 40,
        'r': 9,
        'o': ['esc'],
      }),
    )!;

    expect(share.layout.columns, kToolbarMaxColumns);
    expect(share.layout.rows, kToolbarMaxRows);
  });

  test('a long name is cut and trimmed', () {
    final share = parseToolbarShareLink(
      _link({
        'v': 1,
        'n': '  ${'x' * 80}  ',
        'c': 5,
        'r': 2,
        'o': ['esc'],
      }),
    )!;

    expect(share.name.length, 40);
  });

  test('anything else is not a toolbar', () {
    for (final raw in [
      'ssh://root@example.com',
      'termphin://profile?d=e30',
      'termphin://toolbar',
      'termphin://toolbar?d=not-base64-json',
      _link({
        'v': 2,
        'n': 'Future',
        'c': 5,
        'r': 2,
        'o': ['esc'],
      }),
      _link({
        'v': 1,
        'n': 'Empty',
        'c': 5,
        'r': 2,
        'o': ['', 'snippet:x'],
      }),
      'termphin://toolbar?d=${'A' * 20000}',
    ]) {
      expect(parseToolbarShareLink(raw), isNull, reason: raw);
    }
  });

  test('a toolbar link is recognised even when it cannot be read', () {
    expect(isToolbarShareLink('termphin://toolbar?d=garbage'), isTrue);
    expect(isToolbarShareLink('TERMPHIN://Toolbar'), isTrue);
    expect(isToolbarShareLink('ssh://toolbar'), isFalse);
  });
}
