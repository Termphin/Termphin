import 'dart:async';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart' as re;

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/settings/editor_settings.dart';
import '../../services/settings/setting.dart';
import '../../services/settings/terminal_settings.dart';
import '../../utils/editor_languages.dart';
import '../../widgets/sftp/code_editor_style.dart';
import '../../widgets/terminal/pinch_font_zoom.dart';
import '../../widgets/terminal/terminal_scheme_theme.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_header.dart';
import '../../widgets/ui/settings_controls.dart';
import '../../widgets/ui/stepper_row.dart';

/// Canned file for the preview: it stands for a file, it is not copy.
const _sample = '''services:
  api:
    image: ghcr.io/acme/api:2.14.1
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      DB_POOL_MAX: 50
      LOG_LEVEL: info
''';

/// How the SFTP text editor draws a file, with the editor itself above the
/// controls as the preview - the terminal appearance screen's arrangement.
class EditorSettingsScreen extends StatefulWidget {
  const EditorSettingsScreen({super.key});

  @override
  State<EditorSettingsScreen> createState() => _EditorSettingsScreenState();
}

/// The preview is drawn in the terminal's scheme, as the editor is - a
/// preview in the app theme would show colours the editor never uses.
class _EditorSettingsScreenState extends State<EditorSettingsScreen> {
  final _settings = editorSettings;
  late final _preview = re.CodeLineEditingController.fromText(_sample);

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.editorSettings));
    _settings.changes.addListener(_onChanged);
  }

  @override
  void dispose() {
    _settings.changes.removeListener(_onChanged);
    _preview.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _write<T>(Setting<T> setting, T value) => unawaited(setting.set(value));

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final fontSize = _settings.fontSize.value;
    return Scaffold(
      appBar: AppBar(title: Text(t.settings.textEditor)),
      body: SafeArea(
        top: false,
        child: ContentGutter(
          builder: (context, gutter) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12).add(gutter),
                child: SizedBox(
                  key: const ValueKey('editorPreview'),
                  height: 188,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: TerminalSchemeTheme(
                      child: Builder(
                        builder: (context) => PinchFontZoom(
                          fontSize: fontSize,
                          min: kEditorMinFontSize,
                          max: kEditorMaxFontSize,
                          onChanged: (v) => _write(_settings.fontSize, v),
                          child: re.CodeEditor(
                            controller: _preview,
                            readOnly: true,
                            wordWrap: _settings.wordWrap.value,
                            style: codeEditorStyle(
                              context,
                              fontSize: fontSize,
                              language: editorLanguageForExtension('yaml'),
                            ),
                            padding: const EdgeInsets.all(12),
                            indicatorBuilder: editorLineNumbers(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32).add(gutter),
                  children: [
                    SectionHeader(t.settings.editorStyle),
                    const SizedBox(height: 10),
                    AppCard(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SettingsDropdownField(
                              label: t.settings.font,
                              value: _settings.fontFamily.value,
                              labels: kTerminalFontLabels,
                              itemsInOwnFont: true,
                              onChanged: (v) => _write(_settings.fontFamily, v),
                            ),
                            const SizedBox(height: 16),
                            ValueStepperRow(
                              label: t.settings.fontSize,
                              value: fontSize,
                              display: fontSize.toStringAsFixed(1),
                              min: kEditorMinFontSize,
                              max: kEditorMaxFontSize,
                              step: 0.5,
                              onChanged: (v) => _write(_settings.fontSize, v),
                            ),
                            ValueStepperRow(
                              label: t.settings.lineHeight,
                              value: _settings.lineHeight.value,
                              display: _settings.lineHeight.value
                                  .toStringAsFixed(2),
                              min: 1.0,
                              max: 2.2,
                              step: 0.05,
                              onChanged: (v) => _write(_settings.lineHeight, v),
                            ),
                            ValueStepperRow(
                              label: t.settings.editorTabWidth,
                              value: _settings.tabWidth.value.toDouble(),
                              display: '${_settings.tabWidth.value}',
                              min: 1,
                              max: 8,
                              step: 1,
                              onChanged: (v) =>
                                  _write(_settings.tabWidth, v.round()),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                t.settings.editorPinchHint,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            SettingsSwitchRow(
                              label: t.settings.editorLineNumbers,
                              value: _settings.lineNumbers.value,
                              onChanged: (v) =>
                                  _write(_settings.lineNumbers, v),
                            ),
                            SettingsSwitchRow(
                              label: t.settings.editorWordWrap,
                              subtitle: t.settings.editorWordWrapSubtitle,
                              value: _settings.wordWrap.value,
                              onChanged: (v) => _write(_settings.wordWrap, v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
