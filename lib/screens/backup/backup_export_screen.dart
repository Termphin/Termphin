import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/backup/export_service.dart';
import '../../theme/theme.dart';
import '../../widgets/backup/backup_import_options.dart' show formatBackupDate;
import '../../widgets/backup/backup_option_tile.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/app_form_field.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/backup_action_bar.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/large_title_scaffold.dart';

/// Picks what goes into a backup file and writes it.
class BackupExportScreen extends StatefulWidget {
  const BackupExportScreen({super.key});

  @override
  State<BackupExportScreen> createState() => _BackupExportScreenState();
}

class _BackupExportScreenState extends State<BackupExportScreen> {
  bool _includeProfiles = true;
  bool _includePasswords = false;
  bool _includeInlineKeys = false;
  bool _includeSshKeys = true;
  bool _includeSnippets = true;
  bool _includeKnownHosts = false;
  bool _includeTerminalSettings = true;
  bool _includeAppPreferences = true;

  bool _encrypt = false;
  final _passphrase = TextEditingController();
  final _passphraseConfirm = TextEditingController();
  String? _passphraseError;

  bool _exporting = false;

  final _service = ExportService();

  /// How many records each section holds, so the screen can say what is about
  /// to be written instead of leaving it to be discovered in the file.
  BackupContents? _contents;

  @override
  void initState() {
    super.initState();
    unawaited(lastBackupAtSetting.load());
    unawaited(_loadContents());
  }

  Future<void> _loadContents() async {
    final contents = await _service.contents();
    if (mounted) setState(() => _contents = contents);
  }

  @override
  void dispose() {
    _passphrase.dispose();
    _passphraseConfirm.dispose();
    super.dispose();
  }

  ExportOptions get _options => ExportOptions(
    includeProfiles: _includeProfiles,
    includePasswords: _includePasswords,
    includeInlinePrivateKeys: _includeInlineKeys,
    includeSshKeys: _includeSshKeys,
    includeSnippets: _includeSnippets,
    includeKnownHosts: _includeKnownHosts,
    includeTerminalSettings: _includeTerminalSettings,
    includeAppPreferences: _includeAppPreferences,
  );

  /// Null when the passphrase pair is usable - either encryption is off, or
  /// both fields agree and are long enough.
  String? _validatePassphrase(Translations t) {
    if (!_encrypt) return null;
    if (_passphrase.text.length < 8) return t.exportScreen.passphraseTooShort;
    if (_passphrase.text != _passphraseConfirm.text) {
      return t.exportScreen.passphraseMismatch;
    }
    return null;
  }

  /// Writes the selected sections to a file, asking for confirmation first if
  /// secrets would be written in the clear - a decision, not a side effect of
  /// leaving a switch on, so it is asked once rather than only stated in a
  /// banner.
  Future<void> _export() async {
    if (_exporting) return;
    final t = Translations.of(context);
    final options = _options;
    if (options.isEmpty) {
      AppNotifications.error(context, t.exportScreen.exportNothingSelected);
      return;
    }

    final passphraseError = _validatePassphrase(t);
    if (passphraseError != null) {
      setState(() => _passphraseError = passphraseError);
      return;
    }
    setState(() => _passphraseError = null);

    if (!_encrypt && options.containsSecrets) {
      final proceed = await _confirmPlaintextSecrets(t);
      if (!mounted || !proceed) return;
    }

    setState(() => _exporting = true);
    try {
      final json = await _service.exportToJson(
        options,
        passphrase: _encrypt ? _passphrase.text : null,
      );

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final fileName = 'termphin_backup_$timestamp.json';

      final savePath = await FilePicker.saveFile(
        dialogTitle: t.exportScreen.saveDialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );

      if (savePath == null) return;
      await lastBackupAtSetting.set(DateTime.now().toIso8601String());

      if (!mounted) return;
      AppNotifications.success(context, t.exportScreen.exportSuccess);
    } catch (e) {
      if (!mounted) return;
      AppNotifications.error(
        context,
        t.exportScreen.exportFailed(error: e.toString()),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<bool> _confirmPlaintextSecrets(Translations t) {
    return showConfirmDialog(
      context,
      title: t.exportScreen.confirmPlaintextTitle,
      message: t.exportScreen.confirmPlaintextBody,
      confirmLabel: t.exportScreen.confirmPlaintextContinue,
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final options = _options;
    return Scaffold(
      appBar: AppBar(title: Text(t.exportScreen.exportSection)),
      body: SafeArea(
        child: ContentGutter(
          builder: (context, gutter) => Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space20,
                    AppTheme.space16,
                    AppTheme.space20,
                    AppTheme.space20,
                  ).add(gutter),
                  children: [
                    Text(
                      t.exportScreen.exportInstructions,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.colors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppTheme.space12),
                    AppCard.fields(
                      children: [
                        BackupOptionTile(
                          icon: PhosphorIconsFill.monitor,
                          title: t.exportScreen.includeSshProfiles,
                          subtitle: t.exportScreen.includeSshProfilesSubtitle,
                          value: _includeProfiles,
                          onChanged: (v) => setState(() {
                            _includeProfiles = v;
                            if (!v) {
                              _includePasswords = false;
                              _includeInlineKeys = false;
                            }
                          }),
                        ),
                        const AppDivider(indent: AppTheme.space48),
                        BackupOptionTile(
                          icon: PhosphorIconsFill.lock,
                          title: t.exportScreen.includePasswords,
                          subtitle: t.exportScreen.includePasswordsSubtitle,
                          value: _includePasswords,
                          enabled: _includeProfiles,
                          sensitive: true,
                          onChanged: (v) =>
                              setState(() => _includePasswords = v),
                        ),
                        const AppDivider(indent: AppTheme.space48),
                        BackupOptionTile(
                          icon: PhosphorIconsFill.key,
                          title: t.exportScreen.includeInlineKeys,
                          subtitle: t.exportScreen.includeInlineKeysSubtitle,
                          value: _includeInlineKeys,
                          enabled: _includeProfiles,
                          sensitive: true,
                          onChanged: (v) =>
                              setState(() => _includeInlineKeys = v),
                        ),
                        const AppDivider(indent: AppTheme.space48),
                        BackupOptionTile(
                          icon: PhosphorIconsFill.key,
                          title: t.exportScreen.includeSshKeys,
                          subtitle: t.exportScreen.includeSshKeysSubtitle,
                          value: _includeSshKeys,
                          sensitive: true,
                          onChanged: (v) => setState(() => _includeSshKeys = v),
                        ),
                        const AppDivider(indent: AppTheme.space48),
                        BackupOptionTile(
                          icon: PhosphorIconsFill.magicWand,
                          title: t.exportScreen.includeSnippets,
                          subtitle: t.exportScreen.includeSnippetsSubtitle,
                          value: _includeSnippets,
                          onChanged: (v) =>
                              setState(() => _includeSnippets = v),
                        ),
                        const AppDivider(indent: AppTheme.space48),
                        BackupOptionTile(
                          icon: PhosphorIconsFill.shieldCheck,
                          title: t.exportScreen.includeKnownHosts,
                          subtitle: t.exportScreen.includeKnownHostsSubtitle,
                          value: _includeKnownHosts,
                          onChanged: (v) =>
                              setState(() => _includeKnownHosts = v),
                        ),
                        const AppDivider(indent: AppTheme.space48),
                        BackupOptionTile(
                          icon: PhosphorIconsFill.terminal,
                          title: t.exportScreen.includeTerminalSettings,
                          subtitle:
                              t.exportScreen.includeTerminalSettingsSubtitle,
                          value: _includeTerminalSettings,
                          onChanged: (v) =>
                              setState(() => _includeTerminalSettings = v),
                        ),
                        const AppDivider(indent: AppTheme.space48),
                        BackupOptionTile(
                          icon: PhosphorIconsFill.sliders,
                          title: t.exportScreen.includeAppPreferences,
                          subtitle:
                              t.exportScreen.includeAppPreferencesSubtitle,
                          value: _includeAppPreferences,
                          onChanged: (v) =>
                              setState(() => _includeAppPreferences = v),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppTheme.space10),
                    AppCard.fields(
                      children: [
                        BackupOptionTile(
                          icon: PhosphorIconsFill.lockKey,
                          title: t.exportScreen.encryptTitle,
                          subtitle: t.exportScreen.encryptSubtitle,
                          value: _encrypt,
                          onChanged: (v) => setState(() {
                            _encrypt = v;
                            _passphraseError = null;
                          }),
                        ),
                        if (_encrypt)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.space14,
                              0,
                              AppTheme.space14,
                              AppTheme.space14,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppFormField(
                                  controller: _passphrase,
                                  label: t.exportScreen.passphraseLabel,
                                  icon: PhosphorIconsFill.lockKey,
                                  obscure: true,
                                  onChanged: (_) => _clearPassphraseError(),
                                ),
                                const SizedBox(height: AppTheme.space10),
                                AppFormField(
                                  controller: _passphraseConfirm,
                                  label: t.exportScreen.passphraseConfirmLabel,
                                  icon: PhosphorIconsFill.lockKey,
                                  obscure: true,
                                  action: TextInputAction.done,
                                  onChanged: (_) => _clearPassphraseError(),
                                ),
                                if (_passphraseError case final error?) ...[
                                  const SizedBox(height: AppTheme.space8),
                                  Text(
                                    error,
                                    style: TextStyle(
                                      fontSize: AppTheme.font12,
                                      color: context.colors.error,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),

                    if (_summary(t, options) case final summary?) ...[
                      const SizedBox(height: AppTheme.space10),
                      Text(
                        t.exportScreen.estimatedContents(summary: summary),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],

                    if (options.containsSecrets && !_encrypt) ...[
                      const SizedBox(height: AppTheme.space10),
                      BackupWarningBanner(t.exportScreen.sensitiveWarning),
                    ],

                    const SizedBox(height: AppTheme.space10),
                    ValueListenableBuilder<String>(
                      valueListenable: lastBackupAtSetting,
                      builder: (context, stored, _) {
                        final at = DateTime.tryParse(stored);
                        return Text(
                          at == null
                              ? t.exportScreen.lastBackupNever
                              : t.exportScreen.lastBackup(
                                  date: formatBackupDate(at),
                                ),
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: gutter,
                child: BackupActionBar(
                  icon: PhosphorIconsFill.shareNetwork,
                  label: _exporting
                      ? t.exportScreen.exporting
                      : t.exportScreen.exportButton,
                  busy: _exporting,
                  onPressed: _exporting || options.isEmpty ? null : _export,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The record counts the current selection would write, or null before the
  /// counts are in or when nothing with records is selected.
  String? _summary(Translations t, ExportOptions options) {
    final contents = _contents;
    if (contents == null) return null;
    final parts = [
      if (options.includeProfiles)
        t.exportScreen.profileCount(n: contents.profiles),
      if (options.includeSshKeys) t.exportScreen.keyCount(n: contents.sshKeys),
      if (options.includeSnippets)
        t.exportScreen.snippetCount(n: contents.snippets),
      if (options.includeKnownHosts)
        t.exportScreen.knownHostCount(n: contents.knownHosts),
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  void _clearPassphraseError() {
    if (_passphraseError != null) setState(() => _passphraseError = null);
  }
}
