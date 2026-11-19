import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/platform_info.dart';

/// A phone and a desktop want text set differently - 11pt in a phone's
/// terminal is cramped at a desk - so a backup keeps how text is set apart for
/// each, and restoring one onto the other leaves those alone.
enum FormFactor { mobile, desktop }

/// A tablet counts as mobile: it gets the phone's presentation.
FormFactor get currentFormFactor =>
    isDesktopPlatform ? FormFactor.desktop : FormFactor.mobile;

/// The fields of the `terminalSettings` section that belong to one form
/// factor. The rest (scheme, cursor, predictive echo) are shared.
const kTerminalFormFactorFields = [
  'fontFamily',
  'fontSize',
  'lineHeight',
  'sidePadding',
];

/// The fields of the `appPreferences` section that belong to one form factor.
const kEditorFormFactorFields = [
  'editorFontFamily',
  'editorFontSize',
  'editorLineHeight',
];

/// Where a backup keeps the desktop's values: nested in the section, under
/// these keys, while the flat fields carry the phone's. A build that predates
/// the split reads the flat fields - a phone's, which is all it ever was - and
/// does not see these.
const kDesktopTerminalKey = 'desktop';
const kDesktopEditorKey = 'desktopEditor';

/// The other form factor's values, from the last backup restored here.
///
/// A phone has no use for a desktop's font sizes, but a backup taken on it
/// has to carry them on, or restoring a desktop's backup onto a phone and
/// backing the phone up would lose them. Device state, outside every
/// `Setting`: it is only ever written by an import and read by an export.
class OtherFormFactorStore {
  const OtherFormFactorStore();

  static const prefsKey = 'backup_other_form_factor';
  static const terminal = 'terminal';
  static const editor = 'editor';

  Future<Map<String, dynamic>> _all() async {
    final raw = (await SharedPreferences.getInstance()).getString(prefsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } on FormatException {
      return {};
    }
  }

  Future<Map<String, dynamic>?> read(String section) async {
    final values = (await _all())[section];
    return values is Map ? Map<String, dynamic>.from(values) : null;
  }

  Future<void> write(String section, Map<String, dynamic> values) async {
    final all = await _all();
    all[section] = values;
    await (await SharedPreferences.getInstance()).setString(
      prefsKey,
      jsonEncode(all),
    );
  }
}

/// [fields] out of [section], where present.
Map<String, dynamic> pickFields(
  Map<String, dynamic> section,
  List<String> fields,
) => {
  for (final field in fields)
    if (section.containsKey(field)) field: section[field],
};
