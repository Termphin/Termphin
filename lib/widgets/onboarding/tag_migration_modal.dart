import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/app/tag_migration_service.dart';
import '../../theme/theme.dart';
import '../ui/app_divider.dart';

/// A ceiling, not a height: four tags are four rows tall. Past this the list
/// scrolls inside the card rather than growing the dialog off a short screen.
const _kMaxListHeight = 268.0;

/// Asks which legacy tags become groups, and completes once answered.
///
/// `barrierDismissible: false` for the same reason the what's-new popup is:
/// this one decides what happens to the user's data, so a stray tap outside
/// must not answer it.
Future<void> showTagMigrationModal(
  BuildContext context,
  TagMigrationPlan plan, {
  TagMigrationService? service,
}) {
  if (plan.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TagMigrationModal(plan: plan, service: service),
  );
}

class TagMigrationModal extends StatefulWidget {
  const TagMigrationModal({super.key, required this.plan, this.service});

  final TagMigrationPlan plan;
  final TagMigrationService? service;

  @override
  State<TagMigrationModal> createState() => _TagMigrationModalState();
}

class _TagMigrationModalState extends State<TagMigrationModal> {
  late final TagMigrationService _service;
  late final Set<String> _selected;
  bool _busy = false;

  /// Starts with everything ticked: the common case is that the user wants
  /// the vocabulary they already chose, and unticking is the deliberate act.
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? TagMigrationService();
    _selected = {for (final tag in widget.plan.tags) tag.name};
  }

  Future<void> _skip() async {
    final t = Translations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.tagMigration.skipDialogTitle),
        content: Text(t.tagMigration.skipDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.tagMigration.skipDialogConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    await _service.skip();
    if (mounted) Navigator.of(context).pop();
  }

  /// Nothing ticked is the same answer as starting fresh, so it asks the
  /// same question rather than leaving a button that promises groups and
  /// makes none.
  Future<void> _primary() async {
    if (_selected.isEmpty) {
      await _skip();
      return;
    }
    setState(() => _busy = true);
    await _service.apply(_selected);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final candidates = widget.plan.tags;

    return Dialog(
      backgroundColor: colors.surfaceElevated,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        side: BorderSide(color: colors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.tagMigration.title,
                    style: textTheme.titleLarge?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.tagMigration.explanation,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.tagMigration.multipleTagsNotice,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _kMaxListHeight),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const AppDivider(indent: 16),
                  itemBuilder: (context, i) {
                    final candidate = candidates[i];
                    return CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      value: _selected.contains(candidate.name),
                      title: Text(
                        candidate.name,
                        style: colors.uiStyle.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.tagMigration.usageCount(n: candidate.totalCount),
                        style: colors.uiStyle.copyWith(
                          fontSize: 13,
                          color: colors.textTertiary,
                        ),
                      ),
                      checkColor: colors.onPrimary,
                      fillColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? colors.primary
                            : null,
                      ),
                      onChanged: _busy
                          ? null
                          : (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(candidate.name);
                              } else {
                                _selected.remove(candidate.name);
                              }
                            }),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _primary,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _selected.isNotEmpty
                                ? t.tagMigration.createGroups
                                : t.tagMigration.startFresh,
                          ),
                  ),
                  if (_selected.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _busy ? null : _skip,
                      child: Text(t.tagMigration.startFresh),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
