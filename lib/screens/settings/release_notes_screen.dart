import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/app/release_notes_service.dart';
import '../../theme/theme.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_header.dart';

/// Full history of release notes, opened from Settings.
///
/// This is the changelog proper - every version, every category, bugfixes
/// and all. The post-update popup is a different artefact entirely: see
/// `whats_new_service.dart`, which is hand-written per release and only ever
/// covers new features.
class ReleaseNotesScreen extends StatefulWidget {
  const ReleaseNotesScreen({super.key});

  @override
  State<ReleaseNotesScreen> createState() => _ReleaseNotesScreenState();
}

class _ReleaseNotesScreenState extends State<ReleaseNotesScreen> {
  List<ReleaseNoteEntry>? _entries;

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.releaseNotes));
    _load();
  }

  Future<void> _load() async {
    final entries = await ReleaseNotesService.instance.allEntries();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(title: Text(t.settings.releaseNotes)),
      body: SafeArea(
        top: false,
        child: entries == null
            ? const SizedBox.shrink()
            : ContentGutter(
                builder: (context, gutter) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space16,
                    AppTheme.space16,
                    AppTheme.space16,
                    AppTheme.space32,
                  ).add(gutter),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppTheme.space12),
                    child: AppDivider(),
                  ),
                  itemBuilder: (_, index) => _VersionSection(
                    entry: entries[index],
                    initiallyExpanded: index == 0,
                  ),
                ),
              ),
      ),
    );
  }
}

class _VersionSection extends StatefulWidget {
  const _VersionSection({required this.entry, required this.initiallyExpanded});

  final ReleaseNoteEntry entry;
  final bool initiallyExpanded;

  @override
  State<_VersionSection> createState() => _VersionSectionState();
}

class _VersionSectionState extends State<_VersionSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.space6),
            child: Row(
              children: [
                Text(
                  'v${widget.entry.version}',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: AppTheme.interactiveDuration,
                  child: Icon(
                    PhosphorIconsRegular.caretDown,
                    size: AppTheme.icon18,
                    color: context.colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: AppTheme.interactiveDuration,
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: _expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final category in widget.entry.categories)
                      _CategorySection(category: category),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

(IconData, Color) _categoryStyle(BuildContext context, String label) {
  return switch (label) {
    'Added' => (PhosphorIconsRegular.plusCircle, context.colors.success),
    'Changed' => (PhosphorIconsFill.arrowsClockwise, context.colors.primary),
    'Deprecated' => (PhosphorIconsFill.warning, context.colors.warning),
    'Removed' => (PhosphorIconsFill.minusCircle, context.colors.error),
    'Fixed' => (PhosphorIconsFill.wrench, context.colors.primary),
    'Security' => (PhosphorIconsFill.shieldCheck, context.colors.success),
    _ => (PhosphorIconsRegular.checkCircle, context.colors.primary),
  };
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category});

  final ReleaseNoteCategory category;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (icon, color) = _categoryStyle(context, category.label);
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(category.label, icon: icon, color: color),
          const SizedBox(height: AppTheme.space8),
          for (final item in category.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: textTheme.bodyMedium),
                  Expanded(child: Text(item, style: textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
