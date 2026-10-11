import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/settings/terminal_settings.dart';

void main() {
  final settings = terminalSettings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
  });

  test('loads defaults from empty preferences', () async {
    await settings.load();

    expect(settings.scheme.value, settings.scheme.fallback);
    expect(settings.lineHeight.value, settings.lineHeight.fallback);
    expect(settings.sidePadding.value, settings.sidePadding.fallback);
    expect(settings.cursorStyle.value, settings.cursorStyle.fallback);
    expect(settings.cursorBlink.value, isTrue);
    expect(settings.predictiveEcho.value, isTrue);
    expect(settings.fontFamily.value, settings.fontFamily.fallback);
  });

  test('clamps ranges and replaces unsupported enum values', () async {
    SharedPreferences.setMockInitialValues({
      kTerminalSchemePrefsKey: 'unknown',
      kTerminalLineHeightPrefsKey: 5.0,
      kTerminalSidePaddingPrefsKey: -5.0,
      kTerminalCursorStylePrefsKey: 'circle',
    });

    await settings.load();

    expect(settings.scheme.value, settings.scheme.fallback);
    expect(settings.lineHeight.value, 2.0);
    expect(settings.sidePadding.value, 0);
    expect(settings.cursorStyle.value, settings.cursorStyle.fallback);
  });

  test('every setting round-trips through storage', () async {
    await settings.scheme.set('dracula');
    await settings.fontFamily.set('FiraCodeNerdFontMono');
    await settings.lineHeight.set(1.25);
    await settings.sidePadding.set(10);
    await settings.cursorStyle.set('bar');
    await settings.cursorBlink.set(false);
    await settings.predictiveEcho.set(false);

    await settings.load();

    expect(settings.scheme.value, 'dracula');
    expect(settings.fontFamily.value, 'FiraCodeNerdFontMono');
    expect(settings.lineHeight.value, 1.25);
    expect(settings.sidePadding.value, 10);
    expect(settings.cursorStyle.value, 'bar');
    expect(settings.cursorBlink.value, isFalse);
    expect(settings.predictiveEcho.value, isFalse);
  });

  test('changing any one of them fires the shared listenable', () async {
    var fired = 0;
    void onChange() => fired++;
    settings.changes.addListener(onChange);
    addTearDown(() => settings.changes.removeListener(onChange));

    await settings.scheme.set('nord');
    await settings.cursorBlink.set(false);

    expect(fired, 2);
  });
}
