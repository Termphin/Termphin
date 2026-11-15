import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../services/analytics/analytics_service.dart';
import '../../theme/theme.dart';
import '../../widgets/settings/setting_reveal.dart';
import '../../widgets/ui/large_title_scaffold.dart';

/// One category of Settings on a screen of its own: a large title, a line
/// saying what is in it, and the sections that make it up, each owning its
/// own state as they did on the one long screen.
///
/// A plain [Column] in a [SingleChildScrollView] rather than a [ListView],
/// for the reason [SettingsScreen] gives: every section's own load starts as
/// the screen opens, not when a lazy sliver scrolls it into view.
class SettingsCategoryScreen extends StatefulWidget {
  const SettingsCategoryScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.analyticsScreen,
    required this.sections,
    this.focus,
  });

  final String title;
  final String subtitle;
  final AnalyticsScreen analyticsScreen;

  /// Spaced apart here; each brings its own header when it needs one.
  final List<Widget> sections;

  /// The title of a setting to scroll to and mark, when search opened it.
  final String? focus;

  @override
  State<SettingsCategoryScreen> createState() => _SettingsCategoryScreenState();
}

class _SettingsCategoryScreenState extends State<SettingsCategoryScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.screen(widget.analyticsScreen));
  }

  @override
  Widget build(BuildContext context) {
    return LargeTitleScaffold(
      title: widget.title,
      bodyBuilder: (context, scrollController, gutter) => SettingReveal(
        focus: widget.focus,
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space16,
            0,
            AppTheme.space16,
            AppTheme.space32,
          ).add(gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LargeTitleHeader(
                title: widget.title,
                subtitle: widget.subtitle,
                padding: const EdgeInsets.only(
                  top: AppTheme.space24,
                  bottom: AppTheme.space8,
                ),
              ),
              const SizedBox(height: AppTheme.space16),
              for (final (index, section) in widget.sections.indexed) ...[
                if (index > 0) const SizedBox(height: AppTheme.space20),
                section,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
