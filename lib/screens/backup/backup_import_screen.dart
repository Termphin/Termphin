import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/groups_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/snippets_provider.dart';
import '../../services/backup/backup_crypto.dart';
import '../../services/backup/export_service.dart';
import '../../theme/theme.dart';
import '../../widgets/backup/backup_import_options.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/backup_action_bar.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/large_title_scaffold.dart';

/// Reads a backup file and puts the chosen parts of it onto this device.
///
/// The file is picked first and previewed in place: what it holds, what is
/// already here, and what to do about the overlap.
class BackupImportScreen extends ConsumerStatefulWidget {
  const BackupImportScreen({super.key});

  @override
  ConsumerState<BackupImportScreen> createState() => _BackupImportScreenState();
}

class _BackupImportScreenState extends ConsumerState<BackupImportScreen> {
  final _service = ExportService();

  ImportPreview? _preview;
  ImportOptions? _options;
  bool _busy = false;

  /// Lets the user choose a backup file and previews what it holds. Ignored
  /// while already busy, since a second picker over the first would race the
  /// same storage.
  Future<void> _pickFile() async {
    if (_busy) return;
    final t = Translations.of(context);

    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;

    setState(() => _busy = true);
    try {
      final String raw;
      try {
        raw = utf8.decode(await result.first.readAsBytes());
      } catch (_) {
        if (!mounted) return;
        AppNotifications.error(context, t.exportScreen.invalidFile);
        return;
      }

      final preview = await _inspect(raw, t);
      if (preview == null || !mounted) return;
      if (preview.isEmpty) {
        AppNotifications.error(context, t.exportScreen.emptyBackup);
        return;
      }
      setState(() {
        _preview = preview;
        _options = null;
      });
    } catch (e) {
      if (!mounted) return;
      AppNotifications.error(
        context,
        t.exportScreen.importFailed(error: e.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reads the file, asking for a passphrase for as long as the one given
  /// does not open it. Null means the file cannot be used or the user backed
  /// out, and the message has already been shown.
  Future<ImportPreview?> _inspect(String raw, Translations t) async {
    String? passphrase;
    while (true) {
      try {
        return await _service.inspect(raw, passphrase: passphrase);
      } on BackupFormatException catch (e) {
        if (!mounted) return null;
        switch (e.problem) {
          case BackupProblem.passphraseRequired:
          case BackupProblem.wrongPassphrase:
            passphrase = await showBackupPassphraseSheet(
              context,
              wrong: e.problem == BackupProblem.wrongPassphrase,
            );
            if (passphrase == null || !mounted) return null;
          case BackupProblem.unsupportedVersion:
            AppNotifications.error(context, t.exportScreen.unsupportedVersion);
            return null;
          case BackupProblem.notABackup:
            AppNotifications.error(context, t.exportScreen.invalidFile);
            return null;
        }
      }
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    final options = _options;
    if (_busy || preview == null || options == null) return;
    final t = Translations.of(context);

    setState(() => _busy = true);
    try {
      final outcome = await _service.importBackup(preview, options);
      await ref.read(profileGroupsProvider.notifier).loadGroups();
      await ref.read(profilesProvider.notifier).loadProfiles();
      await ref.read(snippetsProvider.notifier).loadSnippets();
      if (!mounted) return;
      _report(outcome, t);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppNotifications.error(
        context,
        t.exportScreen.importFailed(error: e.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows the outcome of an import, then separately flags any profile that
  /// cannot reach its key or its bastion - a broken import, not a successful
  /// one, so it is said out loud rather than discovered at the next
  /// connection attempt.
  void _report(ImportResult outcome, Translations t) {
    if (!outcome.changedAnything) {
      AppNotifications.info(context, t.exportScreen.importNothingChanged);
    } else {
      AppNotifications.success(
        context,
        t.exportScreen.importSuccess(
          added:
              outcome.profiles.added +
              outcome.sshKeys.added +
              outcome.snippets.added +
              outcome.knownHosts.added +
              outcome.groups.added,
          replaced:
              outcome.profiles.replaced +
              outcome.sshKeys.replaced +
              outcome.snippets.replaced +
              outcome.knownHosts.replaced +
              outcome.groups.replaced,
          skipped: outcome.skippedRecords,
        ),
      );
    }
    if (outcome.profilesMissingKey.isNotEmpty) {
      AppNotifications.show(
        context,
        t.exportScreen.importMissingKeys(
          names: outcome.profilesMissingKey.join(', '),
        ),
        kind: AppNotificationKind.warning,
      );
    }
    if (outcome.profilesMissingJumpHost.isNotEmpty) {
      AppNotifications.show(
        context,
        t.exportScreen.importMissingJumpHosts(
          names: outcome.profilesMissingJumpHost.join(', '),
        ),
        kind: AppNotificationKind.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: Text(t.exportScreen.importSection)),
      body: SafeArea(
        child: ContentGutter(
          builder: (context, gutter) => Column(
            children: [
              Expanded(
                child: preview == null
                    ? Padding(
                        padding: gutter,
                        child: _EmptyState(busy: _busy),
                      )
                    : ImportOptionsPanel(
                        key: ValueKey(preview),
                        preview: preview,
                        onChanged: (options) =>
                            setState(() => _options = options),
                      ),
              ),
              Padding(
                padding: gutter,
                child: preview == null
                    ? BackupActionBar(
                        icon: PhosphorIconsFill.folderOpen,
                        label: _busy
                            ? t.exportScreen.reading
                            : t.exportScreen.selectFile,
                        busy: _busy,
                        onPressed: _busy ? null : _pickFile,
                      )
                    : BackupActionBar(
                        icon: PhosphorIconsFill.downloadSimple,
                        label: _busy
                            ? t.exportScreen.importing
                            : t.common.import,
                        busy: _busy,
                        onPressed: _busy || _options == null ? null : _import,
                        secondaryLabel: t.exportScreen.chooseAnotherFile,
                        onSecondaryPressed: _busy ? null : _pickFile,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space16,
        AppTheme.space20,
        AppTheme.space20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.exportScreen.importInstructions,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
          Expanded(
            child: EmptyStatePanel(
              icon: PhosphorIconsRegular.folderOpen,
              title: t.exportScreen.noFileChosen,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}
