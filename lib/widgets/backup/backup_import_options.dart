import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/backup/export_service.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/app_form_field.dart';
import '../ui/app_sheet.dart';
import '../ui/large_title_scaffold.dart';
import '../ui/modal_actions.dart';
import '../ui/section_header.dart';
import 'backup_option_tile.dart';

/// Date and time of an export, in the ambient locale's own order rather than
/// a hand-built English string.
String formatBackupDate(DateTime value) {
  final local = value.toLocal();
  return '${DateFormat.yMMMd().format(local)} ${DateFormat.Hm().format(local)}';
}

/// Asks for the passphrase a sealed backup was written with. Null when the
/// user backs out, which is what stops the import.
Future<String?> showBackupPassphraseSheet(
  BuildContext context, {
  bool wrong = false,
}) {
  return showAppSheet<String>(
    context: context,
    builder: (ctx) => _PassphraseSheet(wrong: wrong),
  );
}

class _PassphraseSheet extends StatefulWidget {
  const _PassphraseSheet({required this.wrong});

  final bool wrong;

  @override
  State<_PassphraseSheet> createState() => _PassphraseSheetState();
}

class _PassphraseSheetState extends State<_PassphraseSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text;
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.exportScreen.passphrasePromptTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            widget.wrong
                ? t.exportScreen.passphraseWrong
                : t.exportScreen.passphrasePromptBody,
            style: TextStyle(
              fontSize: 13,
              color: widget.wrong
                  ? context.colors.error
                  : context.colors.textTertiary,
            ),
          ),
          const SizedBox(height: 14),
          AppFormField(
            controller: _controller,
            label: t.exportScreen.passphraseLabel,
            icon: PhosphorIconsFill.lockKey,
            obscure: true,
            autofocus: true,
            action: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          ModalActions(
            layout: ModalActionsLayout.sideBySide,
            secondary: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.common.cancel),
            ),
            primary: ElevatedButton(
              onPressed: _submit,
              child: Text(t.exportScreen.unlock),
            ),
          ),
        ],
      ),
    );
  }
}

/// One record section of the file, with what the user has narrowed it down to.
class _SectionModel {
  _SectionModel({required this.icon, required this.items})
    : selected = {for (final item in items) item.id};

  final IconData icon;
  final List<BackupItem> items;
  final Set<String> selected;

  bool enabled = true;
  bool expanded = false;

  bool get isEmpty => items.isEmpty;
  int get conflicts => items.where((item) => item.exists).length;
  bool get active => enabled && selected.isNotEmpty;
}

/// The scrollable half of the import screen: what the file holds, ticked
/// down to what should come across.
///
/// It owns the selection and reports it up rather than being asked for it,
/// so the screen's Import button - which lives outside the scroll - can be
/// dead until there is something to import.
class ImportOptionsPanel extends StatefulWidget {
  const ImportOptionsPanel({
    super.key,
    required this.preview,
    required this.onChanged,
  });

  final ImportPreview preview;

  /// Null while nothing is selected.
  final ValueChanged<ImportOptions?> onChanged;

  @override
  State<ImportOptionsPanel> createState() => _ImportOptionsPanelState();
}

class _ImportOptionsPanelState extends State<ImportOptionsPanel> {
  late final _profiles = _SectionModel(
    icon: PhosphorIconsFill.monitor,
    items: widget.preview.profiles,
  );
  late final _keys = _SectionModel(
    icon: PhosphorIconsFill.key,
    items: widget.preview.sshKeys,
  );
  late final _snippets = _SectionModel(
    icon: PhosphorIconsFill.magicWand,
    items: widget.preview.snippets,
  );
  late final _hosts = _SectionModel(
    icon: PhosphorIconsFill.shieldCheck,
    items: widget.preview.knownHosts,
  );

  late bool _terminal = widget.preview.hasTerminalSettings;
  late bool _appPreferences = widget.preview.hasAppPreferences;
  ImportConflicts _conflicts = ImportConflicts.skip;

  List<_SectionModel> get _sections => [_profiles, _keys, _snippets, _hosts];

  bool get _anythingSelected =>
      _sections.any((section) => section.active) ||
      (_terminal && widget.preview.hasTerminalSettings) ||
      (_appPreferences && widget.preview.hasAppPreferences);

  /// Publishes the opening selection once mounted, since the screen's
  /// button reads what this reports and needs the initial state, not only
  /// the changes to it.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
  }

  /// Rebuilds and reports; every control calls this instead of `setState`.
  void _change(VoidCallback mutate) {
    setState(mutate);
    _publish();
  }

  void _publish() {
    if (!mounted) return;
    widget.onChanged(
      !_anythingSelected
          ? null
          : ImportOptions(
              mergeProfiles: _profiles.active,
              mergeSshKeys: _keys.active,
              importSnippets: _snippets.active,
              importKnownHosts: _hosts.active,
              importTerminalSettings:
                  _terminal && widget.preview.hasTerminalSettings,
              importAppPreferences:
                  _appPreferences && widget.preview.hasAppPreferences,
              conflicts: _conflicts,
              profileIds: _profiles.selected,
              sshKeyIds: _keys.selected,
              snippetIds: _snippets.selected,
              knownHostSlots: _hosts.selected,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final preview = widget.preview;
    final sectionTitles = <_SectionModel, String>{
      _profiles: t.exportScreen.sectionProfiles,
      _keys: t.exportScreen.sectionSshKeys,
      _snippets: t.exportScreen.sectionSnippets,
      _hosts: t.exportScreen.sectionKnownHosts,
    };
    final present = _sections.where((section) => !section.isEmpty).toList();

    return ContentGutter(
      builder: (context, gutter) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20).add(gutter),
        children: [
          Row(
            children: [
              if (preview.wasEncrypted) ...[
                Icon(
                  PhosphorIconsFill.lockKey,
                  size: 13,
                  color: context.colors.textTertiary,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  t.exportScreen.exportedAt(
                    date: formatBackupDate(preview.exportedAt),
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (preview.containsSecrets) ...[
            BackupWarningBanner(t.exportScreen.importSecretsWarning),
            const SizedBox(height: 14),
          ],
          SectionHeader(t.exportScreen.whatToImport),
          const SizedBox(height: 8),
          AppCard.fields(
            children: [
              for (final section in present) ...[
                if (section != present.first) const AppDivider(indent: 50),
                _sectionTile(section, sectionTitles[section]!),
              ],
              if (preview.hasTerminalSettings) ...[
                if (present.isNotEmpty) const AppDivider(indent: 50),
                BackupOptionTile(
                  icon: PhosphorIconsFill.terminal,
                  title: t.exportScreen.includeTerminalSettings,
                  subtitle: t.exportScreen.includeTerminalSettingsSubtitle,
                  value: _terminal,
                  onChanged: (v) => _change(() => _terminal = v),
                ),
              ],
              if (preview.hasAppPreferences) ...[
                if (present.isNotEmpty || preview.hasTerminalSettings)
                  const AppDivider(indent: 50),
                BackupOptionTile(
                  icon: PhosphorIconsFill.sliders,
                  title: t.exportScreen.includeAppPreferences,
                  subtitle: t.exportScreen.includeAppPreferencesSubtitle,
                  value: _appPreferences,
                  onChanged: (v) => _change(() => _appPreferences = v),
                ),
              ],
            ],
          ),
          if (preview.conflictCount > 0) ...[
            const SizedBox(height: 20),
            SectionHeader(t.exportScreen.conflictsTitle),
            const SizedBox(height: 6),
            Text(
              t.exportScreen.conflictSummary(n: preview.conflictCount),
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            AppCard.fields(
              children: [
                _conflictTile(
                  ImportConflicts.skip,
                  t.exportScreen.conflictsSkip,
                  t.exportScreen.conflictsSkipSubtitle,
                  PhosphorIconsFill.shieldCheck,
                ),
                const AppDivider(indent: 50),
                _conflictTile(
                  ImportConflicts.replace,
                  t.exportScreen.conflictsReplace,
                  t.exportScreen.conflictsReplaceSubtitle,
                  PhosphorIconsFill.arrowsClockwise,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTile(_SectionModel section, String title) {
    final t = Translations.of(context);
    final subtitle = section.conflicts > 0
        ? '${section.selected.length}/${section.items.length} · '
              '${t.exportScreen.conflictSummary(n: section.conflicts)}'
        : '${section.selected.length}/${section.items.length}';
    return BackupOptionTile(
      icon: section.icon,
      title: title,
      subtitle: subtitle,
      value: section.enabled,
      sensitive: section == _keys,
      onChanged: (v) => _change(() {
        section.enabled = v;
        if (v && section.selected.isEmpty) {
          section.selected.addAll(section.items.map((item) => item.id));
        }
      }),
      trailing: section.enabled ? _sectionItems(section) : null,
    );
  }

  Widget _sectionItems(_SectionModel section) {
    final t = Translations.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 50, right: 14, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TextButton(
                style: _compactButton,
                onPressed: () =>
                    setState(() => section.expanded = !section.expanded),
                child: Text(
                  section.expanded
                      ? t.exportScreen.hideItems
                      : t.exportScreen.showItems,
                ),
              ),
              if (section.expanded) ...[
                const Spacer(),
                TextButton(
                  style: _compactButton,
                  onPressed: () => _change(
                    () => section.selected.addAll(
                      section.items.map((item) => item.id),
                    ),
                  ),
                  child: Text(t.exportScreen.selectAll),
                ),
                TextButton(
                  style: _compactButton,
                  onPressed: () => _change(section.selected.clear),
                  child: Text(t.exportScreen.selectNone),
                ),
              ],
            ],
          ),
          if (section.expanded)
            for (final item in section.items) _itemRow(section, item),
        ],
      ),
    );
  }

  Widget _itemRow(_SectionModel section, BackupItem item) {
    final t = Translations.of(context);
    final checked = section.selected.contains(item.id);
    return InkWell(
      onTap: () => _change(() {
        checked
            ? section.selected.remove(item.id)
            : section.selected.add(item.id);
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              checkColor: context.colors.onPrimary,
              fillColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? context.colors.primary
                    : null,
              ),
              onChanged: (value) => _change(() {
                value == true
                    ? section.selected.add(item.id)
                    : section.selected.remove(item.id);
              }),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label.isEmpty ? item.id : item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  if (item.detail case final detail?
                      when detail.trim().isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (item.exists)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.warning.withAlpha(28),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Text(
                  t.exportScreen.alreadyHere,
                  style: TextStyle(fontSize: 10, color: context.colors.warning),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _conflictTile(
    ImportConflicts value,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final selected = _conflicts == value;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(
        icon,
        size: 22,
        color: selected ? context.colors.primary : context.colors.textTertiary,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: context.colors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: context.colors.textTertiary),
      ),
      trailing: selected
          ? Icon(
              PhosphorIconsRegular.check,
              size: 20,
              color: context.colors.primary,
            )
          : null,
      onTap: () => _change(() => _conflicts = value),
    );
  }

  static final _compactButton = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(0, 32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
  );
}
