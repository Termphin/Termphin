import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/assistant/assistant_memory.dart';
import '../../theme/theme.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/settings_tile.dart';

/// Everything Phin noted about one server, a note to a row, each one to
/// remove on its own, and the server's notes all to forget at once.
///
/// Opened from the list in Phin's settings, which shows only how many notes
/// each server has: the notes themselves are long, and a page of them for
/// every server at once is what this replaced.
class PhinServerNotesScreen extends StatefulWidget {
  const PhinServerNotesScreen({
    super.key,
    required this.profileId,
    required this.name,
  });

  final String profileId;

  /// The server as the list showed it - already anonymized where it has to be.
  final String name;

  @override
  State<PhinServerNotesScreen> createState() => _PhinServerNotesScreenState();
}

class _PhinServerNotesScreenState extends State<PhinServerNotesScreen> {
  List<String> _notes = const [];

  @override
  void initState() {
    super.initState();
    assistantMemory.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    assistantMemory.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final notes = await assistantMemory.notesFor(widget.profileId);
    if (mounted) setState(() => _notes = notes);
  }

  Future<void> _forget() async {
    final t = Translations.of(context).assistant;
    final navigator = Navigator.of(context);
    final sure = await showConfirmDialog(
      context,
      title: t.forgetServer,
      message: t.forgetServerConfirm(name: widget.name),
      confirmLabel: t.forget,
      destructive: true,
    );
    if (!sure) return;
    await assistantMemory.forget(widget.profileId);
    if (navigator.mounted) navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    final colors = context.colors;
    return LargeTitleScaffold(
      title: widget.name,
      bodyBuilder: (context, scrollController, gutter) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space16,
          0,
          AppTheme.space16,
          AppTheme.space32,
        ).add(gutter),
        children: [
          LargeTitleHeader(
            title: widget.name,
            subtitle: t.knowsServerSubtitle,
            padding: const EdgeInsets.only(
              top: AppTheme.space24,
              bottom: AppTheme.space8,
            ),
          ),
          if (_notes.isNotEmpty)
            AppCard.fields(
              children: [
                for (final (index, note) in _notes.indexed) ...[
                  if (index > 0) const AppDivider(),
                  _NoteRow(
                    key: ValueKey('phinNote-$index'),
                    note: note,
                    onRemove: () => unawaited(
                      assistantMemory.remove(widget.profileId, note),
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: AppTheme.space24),
          AppCard.fields(
            children: [
              SettingsTile(
                key: const ValueKey('phinForgetServer'),
                icon: PhosphorIconsRegular.trash,
                iconColor: colors.error,
                title: t.forgetServer,
                trailing: SettingsTileTrailing.none,
                onTap: _forget,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One note: a quiet bullet, the text, and an x to remove it.
class _NoteRow extends StatelessWidget {
  const _NoteRow({super.key, required this.note, required this.onRemove});

  final String note;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(
        left: AppTheme.space16,
        top: AppTheme.space12,
        bottom: AppTheme.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.space2),
            child: Icon(
              PhosphorIconsRegular.bookmarkSimple,
              size: AppTheme.icon16,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Text(
              note,
              style: TextStyle(
                fontSize: AppTheme.font14,
                height: 1.45,
                color: colors.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: Translations.of(context).assistant.removeNote,
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: Icon(
              PhosphorIconsRegular.x,
              size: AppTheme.icon16,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
