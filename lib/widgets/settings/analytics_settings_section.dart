import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Analytics section: the consent toggle. The least essential switch on this
/// screen - only About sits below it, which is reading material rather than a
/// setting.
class AnalyticsSettingsSection extends StatefulWidget {
  const AnalyticsSettingsSection({super.key});

  @override
  State<AnalyticsSettingsSection> createState() =>
      _AnalyticsSettingsSectionState();
}

class _AnalyticsSettingsSectionState extends State<AnalyticsSettingsSection> {
  bool _loaded = false;
  bool _analyticsEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final analyticsEnabled = await AnalyticsService.instance.loadConsent();
    if (!mounted) return;
    setState(() {
      _analyticsEnabled = analyticsEnabled ?? false;
      _loaded = true;
    });
  }

  Future<void> _onAnalyticsToggle(bool enabled) async {
    setState(() => _analyticsEnabled = enabled);
    await AnalyticsService.instance.setConsent(enabled);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.analytics),
        const SizedBox(height: AppTheme.space10),
        AppCard(
          child: SettingsSwitchTile(
            title: t.settings.analyticsToggle,
            subtitle: t.settings.analyticsToggleSubtitle,
            value: _analyticsEnabled,
            onChanged: _onAnalyticsToggle,
          ),
        ),
      ],
    );
  }
}
