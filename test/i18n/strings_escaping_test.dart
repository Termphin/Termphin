import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/i18n/strings.g.dart';

void main() {
  /// slang copies a JSON string into a Dart literal as is, so a single
  /// backslash in the JSON becomes an escape in Dart - `\t` a tab.
  test('a Windows path keeps its backslashes', () {
    final t = AppLocale.en.buildSync();
    expect(
      t.settings.agentSheetPointFiles,
      contains(r'%LOCALAPPDATA%\termphin\sessions'),
    );
  });
}
