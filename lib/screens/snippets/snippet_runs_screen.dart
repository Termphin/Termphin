import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/snippet.dart';
import '../../models/snippet_run.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/snippet_runs_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../theme/theme.dart';
import '../../utils/relative_time.dart';
import '../../widgets/snippets/snippet_run_output.dart';
import '../../widgets/ui/app_badge.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/app_dropdown.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/clipboard_and_links.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/large_title_scaffold.dart';

enum _BatchAction { copyCommand, runAgain, forget }

/// History of snippet runs: one card per batch, one row per machine, each with
/// what that host printed.
///
/// Reading is most of what it offers. A run is a one-shot - its session is
/// gone the moment it reports its exit code - so there is no shell here to
/// open; running the same command again starts a fresh batch rather than
/// reviving this one.
class SnippetRunsScreen extends ConsumerWidget {
  const SnippetRunsScreen({super.key});

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.snippets.runsClearAllTitle,
      message: t.snippets.runsClearAllConfirm,
      confirmLabel: t.common.clearAll,
      destructive: true,
    );
    if (!confirmed) return;
    ref.read(snippetRunsProvider.notifier).forgetAll();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final batches = ref.watch(snippetRunsProvider);

    return LargeTitleScaffold(
      title: t.snippets.runsTitle,
      actions: [
        if (batches.isNotEmpty)
          IconButton(
            tooltip: t.common.clearAll,
            onPressed: () => _clearAll(context, ref),
            icon: const Icon(PhosphorIconsRegular.trash),
          ),
      ],
      bodyBuilder: (context, scrollController, gutter) => CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverPadding(
            padding: gutter,
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: LargeTitleHeader(
                    title: t.snippets.runsTitle,
                    subtitle: t.snippets.runsSubtitle,
                  ),
                ),
                if (batches.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStatePanel(
                      icon: PhosphorIconsFill.playCircle,
                      title: t.snippets.runsEmpty,
                      subtitle: t.snippets.runsEmptySubtitle,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.space16,
                      AppTheme.space16,
                      AppTheme.space16,
                      AppTheme.space32,
                    ),
                    sliver: SliverList.separated(
                      itemCount: batches.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppTheme.space12),
                      itemBuilder: (_, index) =>
                          _BatchCard(batch: batches[index]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchCard extends ConsumerStatefulWidget {
  const _BatchCard({required this.batch});

  final SnippetRunBatch batch;

  @override
  ConsumerState<_BatchCard> createState() => _BatchCardState();
}

/// The card shows what was actually sent, placeholders already substituted -
/// the snippet's own text would not say what this run did.
class _BatchCardState extends ConsumerState<_BatchCard> {
  /// Only the rows the user has toggled by hand. Everything else follows
  /// [_expandedByDefault], so a batch that is still working, or that failed,
  /// shows its output without being asked while the ones that simply worked
  /// stay a single line each.
  final _overrides = <String, bool>{};

  bool _expandedByDefault(SnippetRun run) =>
      run.status != SnippetRunStatus.succeeded;

  bool _isExpanded(SnippetRun run) =>
      _overrides[run.id] ?? _expandedByDefault(run);

  Future<void> _copyCommand() async {
    await copyToClipboard(
      context,
      widget.batch.command,
      message: Translations.of(context).snippets.commandCopied,
    );
  }

  /// Starts a fresh batch of the same command on the same machines.
  ///
  /// The command is taken as it was sent, placeholders already filled in, so
  /// this repeats what actually ran rather than re-asking for arguments. A
  /// machine deleted in the meantime is dropped rather than failing the lot.
  void _runAgain() {
    final t = Translations.of(context);
    final wanted = widget.batch.runs.map((run) => run.profileId).toSet();
    final profiles = ref
        .read(profilesProvider)
        .where((profile) => wanted.contains(profile.id))
        .toList();
    if (profiles.isEmpty) {
      AppNotifications.error(context, t.snippets.pickMachinesEmpty);
      return;
    }
    ref
        .read(snippetRunsProvider.notifier)
        .start(
          snippet: Snippet(
            id: widget.batch.id,
            name: widget.batch.snippetName,
            command: widget.batch.command,
            createdAt: DateTime.now(),
          ),
          profiles: profiles,
        );
  }

  Future<void> _forget() async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.snippets.runForgetTitle,
      message: t.snippets.runForgetConfirm(name: widget.batch.snippetName),
      confirmLabel: t.snippets.runForget,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    ref.read(snippetRunsProvider.notifier).forget(widget.batch.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final batch = widget.batch;
    final done = batch.runs.where((run) => run.status.isTerminal).length;
    final running = batch.runs.length - done;

    return AppCard(
      elevated: true,
      clipChild: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space14,
              AppTheme.space12,
              AppTheme.space6,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(batch.snippetName, style: context.colors.itemTitle),
                      const SizedBox(height: AppTheme.space4),
                      Text(
                        '${relativeTime(context, batch.startedAt)} · '
                        '${t.snippets.runSummary(done: done, total: batch.runs.length)}',
                        style: context.colors.uiSmall.copyWith(
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.space8),
                AppActionDropdown<_BatchAction>(
                  tooltip: t.snippets.moreActions,
                  iconSize: AppTheme.icon18,
                  iconColor: context.colors.textTertiary,
                  buttonSize: 36,
                  width: 220,
                  items: [
                    DropdownItem(
                      value: _BatchAction.copyCommand,
                      intrinsicHeight: true,
                      child: AppDropdownItem(
                        icon: PhosphorIconsRegular.copy,
                        label: t.snippets.copyCommand,
                      ),
                    ),
                    DropdownItem(
                      value: _BatchAction.runAgain,
                      intrinsicHeight: true,
                      child: AppDropdownItem(
                        icon: PhosphorIconsRegular.arrowClockwise,
                        label: t.snippets.runAgain,
                      ),
                    ),
                    DropdownItem(
                      value: _BatchAction.forget,
                      intrinsicHeight: true,
                      child: AppDropdownItem(
                        icon: PhosphorIconsRegular.trash,
                        label: t.snippets.runForget,
                        color: context.colors.error,
                      ),
                    ),
                  ],
                  onSelected: (action) {
                    switch (action) {
                      case _BatchAction.copyCommand:
                        _copyCommand();
                      case _BatchAction.runAgain:
                        _runAgain();
                      case _BatchAction.forget:
                        _forget();
                    }
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space14,
              AppTheme.space4,
              AppTheme.space14,
              AppTheme.space12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space10,
                    vertical: AppTheme.space8,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.fieldFill,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: context.colors.surfaceBorder),
                  ),
                  child: Text(
                    batch.command,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.colors.monoSmall.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.space10),
                Wrap(
                  spacing: AppTheme.space6,
                  runSpacing: AppTheme.space6,
                  children: [
                    if (batch.succeededCount > 0)
                      AppBadge(
                        '${batch.succeededCount}',
                        tone: BadgeTone.success,
                        icon: PhosphorIconsRegular.checkCircle,
                      ),
                    if (batch.failedCount > 0)
                      AppBadge(
                        '${batch.failedCount}',
                        tone: BadgeTone.error,
                        icon: PhosphorIconsFill.xCircle,
                      ),
                    if (running > 0)
                      AppBadge(
                        '$running',
                        tone: BadgeTone.highlight,
                        icon: PhosphorIconsFill.circleNotch,
                      ),
                  ],
                ),
              ],
            ),
          ),
          for (final run in batch.runs) ...[
            const AppDivider(),
            _RunRow(
              run: run,
              expanded: _isExpanded(run),
              onToggle: () =>
                  setState(() => _overrides[run.id] = !_isExpanded(run)),
            ),
          ],
        ],
      ),
    );
  }
}

class _RunRow extends ConsumerWidget {
  const _RunRow({
    required this.run,
    required this.expanded,
    required this.onToggle,
  });

  final SnippetRun run;
  final bool expanded;
  final VoidCallback onToggle;

  Future<void> _copyOutput(BuildContext context) async {
    await copyToClipboard(
      context,
      run.output,
      message: Translations.of(context).snippets.outputCopied,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final anonymize = ref.watch(anonymizeProvider);
    final (icon, color, label) = switch (run.status) {
      SnippetRunStatus.pending => (
        PhosphorIconsRegular.clock,
        context.colors.textTertiary,
        t.snippets.runPending,
      ),
      SnippetRunStatus.connecting => (
        PhosphorIconsRegular.plugs,
        context.colors.textSecondary,
        t.snippets.runConnecting,
      ),
      SnippetRunStatus.running => (
        PhosphorIconsRegular.circleNotch,
        context.colors.primary,
        t.snippets.runRunning,
      ),
      SnippetRunStatus.succeeded => (
        PhosphorIconsRegular.checkCircle,
        context.colors.success,
        t.snippets.runSucceeded,
      ),
      SnippetRunStatus.failed => (
        PhosphorIconsFill.xCircle,
        context.colors.error,
        t.snippets.runFailed(code: run.exitCode ?? -1),
      ),
      SnippetRunStatus.error => (
        PhosphorIconsFill.warning,
        context.colors.warning,
        run.error ?? t.snippets.runError,
      ),
    };
    final finishedAt = run.finishedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space14,
              AppTheme.space10,
              AppTheme.space8,
              AppTheme.space10,
            ),
            child: Row(
              children: [
                Icon(icon, size: AppTheme.icon18, color: color),
                const SizedBox(width: AppTheme.space10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        anonymize
                            ? IdentityAnonymizer.name(run.profileId)
                            : run.profileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppTheme.space2),
                      Text(
                        finishedAt == null
                            ? label
                            : '$label · ${relativeTime(context, finishedAt)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: color),
                      ),
                    ],
                  ),
                ),
                if (run.output.isNotEmpty)
                  IconButton(
                    tooltip: t.snippets.copyOutput,
                    onPressed: () => _copyOutput(context),
                    icon: Icon(
                      PhosphorIconsRegular.copy,
                      size: AppTheme.icon16,
                      color: context.colors.textTertiary,
                    ),
                  ),
                Icon(
                  expanded
                      ? PhosphorIconsFill.caretUp
                      : PhosphorIconsFill.caretDown,
                  size: AppTheme.icon16,
                  color: context.colors.textTertiary,
                ),
                const SizedBox(width: AppTheme.space6),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space14,
              0,
              AppTheme.space14,
              AppTheme.space12,
            ),
            child: run.output.isEmpty
                ? Text(
                    t.snippets.runNoOutput,
                    style: context.colors.uiSmall.copyWith(
                      color: context.colors.textTertiary,
                    ),
                  )
                : SnippetRunOutput(
                    key: ValueKey('snippetRunOutput:${run.id}'),
                    text: run.output,
                    follow: !run.status.isTerminal,
                  ),
          ),
      ],
    );
  }
}
