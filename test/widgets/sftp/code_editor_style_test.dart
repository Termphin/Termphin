import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/sftp/code_editor_style.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await terminalSettings.load();
  });

  test('syntax colours are the scheme\'s own ANSI colours', () {
    final dracula = AppTheme.terminalSchemeForId('dracula');
    final palette = schemeHighlightPalette(dracula);

    expect(palette['keyword']!.color, dracula.magenta);
    expect(palette['string']!.color, dracula.green);
    expect(palette['number']!.color, dracula.yellow);
    expect(palette['title']!.color, dracula.blue);
    expect(palette['comment']!.color, dracula.brightBlack);
    expect(palette['root']!.color, dracula.foreground);
  });

  test('a light scheme gets its own dark-on-light colours', () {
    final light = AppTheme.terminalSchemeForId('light');
    expect(schemeHighlightPalette(light)['string']!.color, light.green);
  });

  test('the editor follows the scheme the terminal is set to', () async {
    await terminalSettings.scheme.set('nord');
    final nord = AppTheme.terminalSchemeForId('nord');

    expect(editorHighlightPalette()['keyword']!.color, nord.magenta);
  });
}
