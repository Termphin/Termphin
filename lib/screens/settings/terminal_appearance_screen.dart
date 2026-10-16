import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/settings/setting.dart';
import '../../services/settings/terminal_settings.dart';
import '../../theme/theme.dart';
import '../../widgets/terminal/terminal_preview.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_header.dart';
import '../../widgets/ui/settings_controls.dart';
import '../../widgets/ui/settings_tile.dart';
import '../../widgets/ui/stepper_row.dart';

/// Everything that decides how the terminal looks and behaves, with a live
/// preview above it.
///
/// Its own screen rather than a section of Settings: the preview needs to sit
/// where it stays visible while the controls under it move, which a card in a
/// long settings list cannot do. Every change writes through immediately, so
/// the sessions already open follow along with the preview.
class TerminalAppearanceScreen extends StatefulWidget {
  const TerminalAppearanceScreen({super.key});

  @override
  State<TerminalAppearanceScreen> createState() =>
      _TerminalAppearanceScreenState();
}

class _TerminalAppearanceScreenState extends State<TerminalAppearanceScreen> {
  final _settings = terminalSettings;

  /// No local copies of these values: the preview and the controls read the
  /// settings directly, so what is previewed is what an open session is
  /// being drawn with rather than a snapshot that has to be kept in step.
  String get _schemeId => _settings.scheme.value;
  String get _fontFamily => _settings.fontFamily.value;
  double get _lineHeight => _settings.lineHeight.value;
  double get _sidePadding => _settings.sidePadding.value;
  double get _fontSize => _settings.fontSize.value;
  String get _cursorStyle => _settings.cursorStyle.value;
  bool get _cursorBlink => _settings.cursorBlink.value;
  bool get _predictiveEcho => _settings.predictiveEcho.value;

  @override
  void initState() {
    super.initState();
    unawaited(
      AnalyticsService.instance.screen(AnalyticsScreen.terminalAppearance),
    );
    _settings.changes.addListener(_onChanged);
  }

  @override
  void dispose() {
    _settings.changes.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Writes through immediately - there is no Save button here, and an open
  /// session is expected to follow the preview.
  void _write<T>(Setting<T> setting, T value) => unawaited(setting.set(value));

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final cursorLabels = {
      'block': t.settings.cursorBlock,
      'bar': t.settings.cursorBar,
      'underline': t.settings.cursorUnderline,
    };
    return Scaffold(
      appBar: AppBar(title: Text(t.settings.terminal)),
      body: SafeArea(
        top: false,
        child: ContentGutter(
          builder: (context, gutter) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space16,
                  AppTheme.space16,
                  AppTheme.space16,
                  AppTheme.space12,
                ).add(gutter),
                child: SizedBox(
                  height: 168,
                  width: double.infinity,
                  child: TerminalPreview(
                    key: const ValueKey('terminalPreview'),
                    scheme: AppTheme.terminalSchemeForId(_schemeId),
                    fontFamily: _fontFamily,
                    fontSize: _fontSize,
                    lineHeight: _lineHeight,
                    sidePadding: _sidePadding,
                    cursorStyle: _cursorStyle,
                    cursorBlink: _cursorBlink,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space16,
                    AppTheme.space4,
                    AppTheme.space16,
                    AppTheme.space32,
                  ).add(gutter),
                  children: [
                    SectionHeader(t.settings.terminalStyle),
                    const SizedBox(height: AppTheme.space10),
                    AppCard(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.space14,
                          AppTheme.space14,
                          AppTheme.space14,
                          AppTheme.space8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SettingsDropdownField(
                              label: t.settings.colorScheme,
                              value: _schemeId,
                              labels: kTerminalSchemeLabels,
                              onChanged: (v) => _write(_settings.scheme, v),
                            ),
                            const SizedBox(height: AppTheme.space16),
                            SettingsDropdownField(
                              label: t.settings.font,
                              value: _fontFamily,
                              labels: kTerminalFontLabels,
                              itemFontFamily: (f) => f,
                              onChanged: (v) => _write(_settings.fontFamily, v),
                            ),
                            const SizedBox(height: AppTheme.space16),
                            ValueStepperRow(
                              label: t.settings.fontSize,
                              value: _fontSize,
                              display: _fontSize.toStringAsFixed(1),
                              min: 8,
                              max: 24,
                              step: 0.5,
                              onChanged: (v) => _write(_settings.fontSize, v),
                            ),
                            ValueStepperRow(
                              label: t.settings.lineHeight,
                              value: _lineHeight,
                              display: _lineHeight.toStringAsFixed(2),
                              min: 1.0,
                              max: 2.0,
                              step: 0.05,
                              onChanged: (v) => _write(_settings.lineHeight, v),
                            ),
                            ValueStepperRow(
                              label: t.settings.sidePadding,
                              value: _sidePadding,
                              display: _sidePadding.toStringAsFixed(0),
                              min: 0,
                              max: 16,
                              step: 1,
                              onChanged: (v) =>
                                  _write(_settings.sidePadding, v),
                            ),
                            const SizedBox(height: AppTheme.space12),
                            SettingsDropdownRow(
                              label: t.settings.cursor,
                              value: _cursorStyle,
                              labels: cursorLabels,
                              onChanged: (v) =>
                                  _write(_settings.cursorStyle, v),
                            ),
                            SettingsSwitchTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: t.settings.cursorBlink,
                              value: _cursorBlink,
                              onChanged: (v) =>
                                  _write(_settings.cursorBlink, v),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.space20),
                    SectionHeader(t.settings.terminalBehavior),
                    const SizedBox(height: AppTheme.space10),
                    AppCard(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.space14,
                          AppTheme.space8,
                          AppTheme.space14,
                          AppTheme.space8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SettingsSwitchTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: t.settings.predictiveEcho,
                              subtitle: t.settings.predictiveEchoSubtitle,
                              value: _predictiveEcho,
                              onChanged: (v) =>
                                  _write(_settings.predictiveEcho, v),
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
