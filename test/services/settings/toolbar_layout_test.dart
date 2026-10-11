import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/settings/toolbar_layout.dart';

void main() {
  test('resolves built-in, custom and snippet action ids', () {
    expect(toolbarActionForId('esc')?.bytes, [0x1b]);
    expect(toolbarActionForId('ctrl_c')?.bytes, [0x03]);
    expect(toolbarActionForId('sym_pipe')?.label, '|');

    final text = toolbarActionForId(toolbarCustomActionId(text: 'sudo su'));
    expect(text?.kind, ToolbarActionKind.text);
    expect(text?.payload, 'sudo su');
    expect(text?.label, 'sudo su');

    final snippet = toolbarActionForId(toolbarSnippetActionId('abc-123'));
    expect(snippet?.kind, ToolbarActionKind.snippet);
    expect(snippet?.payload, 'abc-123');

    expect(toolbarActionForId('nope'), isNull);
    expect(toolbarActionForId(''), isNull);
    expect(toolbarActionForId('custom:not-base64!'), isNull);
  });

  test('custom keys carry their label and enter flag', () {
    final id = toolbarCustomActionId(
      text: 'docker ps',
      label: 'PS',
      appendEnter: true,
    );
    final action = toolbarActionForId(id)!;

    expect(action.label, 'PS');
    expect(action.payload, 'docker ps');
    expect(action.appendEnter, isTrue);
    expect(action.bytes.last, 0x0d);
    expect(action.repeatable, isFalse);

    final plain = toolbarActionForId(
      toolbarCustomActionId(text: 'ls', label: '  '),
    )!;
    expect(plain.label, 'ls');
    expect(plain.appendEnter, isFalse);
    expect(plain.bytes, [0x6c, 0x73]);
  });

  test('builds combo keys from modifiers and a key', () {
    final ctrlR = toolbarActionForId(
      toolbarComboActionId(const ToolbarCombo(key: 'r', ctrl: true)),
    )!;
    expect(ctrlR.label, 'Ctrl+R');
    expect(ctrlR.bytes, [0x12]);

    final altF = toolbarActionForId(
      toolbarComboActionId(const ToolbarCombo(key: 'f', alt: true)),
    )!;
    expect(altF.label, 'Alt+F');
    expect(altF.bytes, [0x1b, 0x66]);

    final shiftFour = toolbarActionForId(
      toolbarComboActionId(const ToolbarCombo(key: '4', shift: true)),
    )!;
    expect(shiftFour.bytes, [0x24]);

    final ctrlLeft = toolbarActionForId(
      toolbarComboActionId(const ToolbarCombo(key: 'arrow_left', ctrl: true)),
    )!;
    expect(ctrlLeft.label, 'Ctrl+←');
    expect(ctrlLeft.bytes, [0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x44]);

    final ctrlShiftPageUp = toolbarActionForId(
      toolbarComboActionId(
        const ToolbarCombo(key: 'page_up', ctrl: true, shift: true),
      ),
    )!;
    expect(ctrlShiftPageUp.bytes, [0x1b, 0x5b, 0x35, 0x3b, 0x36, 0x7e]);

    final shiftTab = toolbarActionForId(
      toolbarComboActionId(const ToolbarCombo(key: 'tab', shift: true)),
    )!;
    expect(shiftTab.bytes, [0x1b, 0x5b, 0x5a]);
  });

  test('maps a typed character onto a key plus shift', () {
    final upper = comboFromTypedCharacter('R', ctrl: true);
    expect(upper.key, 'r');
    expect(upper.shift, isTrue);
    expect(upper.ctrl, isTrue);

    final dollar = comboFromTypedCharacter(r'$');
    expect(dollar.key, '4');
    expect(dollar.shift, isTrue);

    final slash = comboFromTypedCharacter('/');
    expect(slash.key, '/');
    expect(slash.shift, isFalse);
    expect(
      toolbarActionForId(
        toolbarComboActionId(const ToolbarCombo(key: '/', ctrl: true)),
      )!.bytes,
      [0x0f],
    );

    expect(comboFromTypedCharacter(' ').key, 'space');
  });

  test('keeps ctrl combos that were built-ins in older versions', () {
    final legacy = toolbarActionForId('ctrl_c')!;

    expect(legacy.bytes, [0x03]);
    expect(legacy.label, 'Ctrl+C');
    expect(kAllBuiltinIds, isNot(contains('ctrl_c')));
  });

  test('a combo with no modifiers reuses the built-in key', () {
    expect(toolbarComboActionId(const ToolbarCombo(key: 'tab')), 'tab');
    expect(
      toolbarComboActionId(const ToolbarCombo(key: 'arrow_left')),
      'arrow_left',
    );
    expect(
      toolbarComboActionId(const ToolbarCombo(key: 'r')),
      startsWith(kToolbarComboPrefix),
    );
  });

  test('rejects combo ids naming a key that does not exist', () {
    expect(parseToolbarComboId('combo:c:nope'), isNull);
    expect(parseToolbarComboId('combo:c'), isNull);
    expect(toolbarActionForId('combo:c:nope'), isNull);

    final parsed = parseToolbarComboId('combo:cas:r')!;
    expect(parsed.ctrl, isTrue);
    expect(parsed.alt, isTrue);
    expect(parsed.shift, isTrue);
    expect(parsed.key, 'r');
  });

  test('still reads text keys saved in the old format', () {
    final action = toolbarActionForId('text:git%20status')!;

    expect(action.kind, ToolbarActionKind.text);
    expect(action.payload, 'git status');
    expect(action.label, 'git status');
  });

  test('keeps custom actions through normalization', () {
    final textId = toolbarCustomActionId(text: 'git status');
    final normalized = normalizeToolbarOrder([
      'esc',
      textId,
      'bogus',
      textId,
    ], slotCount: 6);

    expect(normalized, hasLength(6));
    expect(normalized.where((id) => id == textId), hasLength(1));
    expect(normalized, isNot(contains('bogus')));
  });

  test('hides pages with no keys on them', () {
    const layout = ToolbarLayout(
      order: ['esc', 'tab', '', '', '', '', '', ''],
      columns: 2,
      rows: 2,
      pages: 2,
    );

    expect(layout.visiblePages, [0]);
    expect(layout.isPageEmpty(1), isTrue);
  });

  test('falls back to the first page when every slot is blank', () {
    const layout = ToolbarLayout(
      order: ['', '', '', ''],
      columns: 2,
      rows: 1,
      pages: 2,
    );

    expect(layout.visiblePages, [0]);
  });

  test('reflows keys within their page when the grid is resized', () {
    const layout = ToolbarLayout(
      order: ['esc', 'tab', 'home', 'end', 'f1', 'f2', 'f3', 'f4'],
      columns: 2,
      rows: 2,
      pages: 2,
    );

    final narrower = layout.resized(columns: 3, rows: 1);

    expect(narrower.columns, 3);
    expect(narrower.slotCount, 6);
    expect(narrower.order, ['esc', 'tab', 'home', 'f1', 'f2', 'f3']);
  });

  test('persists grid dimensions and broadcasts the layout', () async {
    SharedPreferences.setMockInitialValues({});
    const layout = ToolbarLayout(
      order: ['esc', 'tab', 'home', 'end', 'f1', 'f2', 'f3', 'f4'],
      columns: 4,
      rows: 1,
      pages: 2,
      buttonHeight: 44,
    );

    await saveToolbarLayout(layout);
    expect(toolbarSettings.layout.value.columns, 4);

    final loaded = (await toolbarSettings.layout.load());
    expect(loaded.columns, 4);
    expect(loaded.rows, 1);
    expect(loaded.pages, 2);
    expect(loaded.buttonHeight, 44);
    expect(loaded.order, ['esc', 'tab', 'home', 'end', 'f1', 'f2', 'f3', 'f4']);
  });

  test('keeps the custom key library and drops broken entries', () async {
    SharedPreferences.setMockInitialValues({});
    final id = toolbarCustomActionId(text: 'htop', appendEnter: true);

    await saveToolbarCustomKeys([id, 'garbage:zzz', id]);
    expect(toolbarSettings.customKeys.value, [id]);
    expect((await toolbarSettings.customKeys.load()), [id]);
  });

  test('editing a custom key updates the library and its slot', () async {
    SharedPreferences.setMockInitialValues({});
    final oldId = toolbarCustomActionId(text: 'htop');
    final newId = toolbarCustomActionId(text: 'htop', label: 'TOP');

    await saveToolbarCustomKeys([oldId]);
    await saveToolbarLayout(
      ToolbarLayout(order: [oldId, ...List.filled(kToolbarSlotCount - 1, '')]),
    );

    await replaceToolbarCustomKey(oldId, newId);

    expect(toolbarSettings.customKeys.value, [newId]);
    expect(toolbarSettings.layout.value.order.first, newId);

    await removeToolbarCustomKey(newId);

    expect(toolbarSettings.customKeys.value, isEmpty);
    expect(toolbarSettings.layout.value.order.first, '');
  });

  test('a custom key edit reaches the profiles that are not in use', () async {
    SharedPreferences.setMockInitialValues({});
    final oldId = toolbarCustomActionId(text: 'htop');
    final newId = toolbarCustomActionId(text: 'htop', label: 'TOP');
    final holding = ToolbarLayout(
      order: [oldId, ...List.filled(kToolbarSlotCount - 1, '')],
    );

    await saveToolbarCustomKeys([oldId]);
    await saveToolbarProfiles(
      ToolbarProfiles(
        profiles: [
          ToolbarProfile(id: 'live', name: 'Live', layout: holding),
          ToolbarProfile(id: 'idle', name: 'Idle', layout: holding),
        ],
        activeId: 'live',
      ),
    );
    await activateToolbarProfile('live');

    await replaceToolbarCustomKey(oldId, newId);

    expect(toolbarProfileLayout('live').order.first, newId);
    expect(toolbarProfileLayout('idle').order.first, newId);

    await removeToolbarCustomKey(newId);

    expect(toolbarProfileLayout('live').order.first, '');
    expect(toolbarProfileLayout('idle').order.first, '');
  });

  test('a layout saved to another profile leaves the live one alone', () async {
    SharedPreferences.setMockInitialValues({});
    await saveToolbarProfiles(
      ToolbarProfiles(
        profiles: [
          ToolbarProfile(
            id: 'live',
            name: 'Live',
            layout: ToolbarLayout.defaults,
          ),
          ToolbarProfile(id: 'idle', name: 'Idle', layout: ToolbarLayout.blank),
        ],
        activeId: 'live',
      ),
    );
    await activateToolbarProfile('live');
    final live = toolbarSettings.layout.value;

    await saveToolbarProfileLayout(
      'idle',
      ToolbarLayout(order: ['f4', ...List.filled(kToolbarSlotCount - 1, '')]),
    );

    expect(toolbarProfileLayout('idle').order.first, 'f4');
    expect(toolbarSettings.layout.value, live);
    expect(toolbarSettings.profiles.value.activeId, 'live');
  });

  test(
    'a layout stored on an idle profile is clamped like the live one',
    () async {
      SharedPreferences.setMockInitialValues({});
      await saveToolbarProfiles(
        ToolbarProfiles(
          profiles: [
            ToolbarProfile(
              id: 'live',
              name: 'Live',
              layout: ToolbarLayout.defaults,
            ),
            ToolbarProfile(
              id: 'idle',
              name: 'Idle',
              layout: ToolbarLayout.blank,
            ),
          ],
          activeId: 'live',
        ),
      );

      await saveToolbarProfileLayout(
        'idle',
        const ToolbarLayout(order: ['esc'], columns: 99, rows: 99, pages: 99),
      );

      final stored = toolbarProfileLayout('idle');
      expect(stored.columns, kToolbarMaxColumns);
      expect(stored.rows, kToolbarMaxRows);
      expect(stored.pages, kToolbarMaxPages);
      expect(stored.order, hasLength(stored.slotCount));
    },
  );

  test('clamps out-of-range dimensions coming from an import', () async {
    SharedPreferences.setMockInitialValues({});

    await saveToolbarLayout(
      const ToolbarLayout(
        order: ['esc'],
        columns: 99,
        rows: 0,
        pages: 42,
        buttonHeight: 500,
      ),
    );

    final loaded = toolbarSettings.layout.value;
    expect(loaded.columns, kToolbarMaxColumns);
    expect(loaded.rows, kToolbarMinRows);
    expect(loaded.pages, kToolbarMaxPages);
    expect(loaded.buttonHeight, kToolbarMaxButtonHeight);
    expect(loaded.order, hasLength(loaded.slotCount));
  });
}
