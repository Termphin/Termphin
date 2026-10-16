import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/settings/upload_settings.dart';
import '../../theme/theme.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/settings_controls.dart';
import '../../widgets/ui/settings_tile.dart';

/// Where an SFTP upload lands. Its own screen because "fast upload" is a
/// feature worth explaining, not just a switch to flip.
class FastUploadSettingsScreen extends StatefulWidget {
  const FastUploadSettingsScreen({super.key});

  @override
  State<FastUploadSettingsScreen> createState() =>
      _FastUploadSettingsScreenState();
}

class _FastUploadSettingsScreenState extends State<FastUploadSettingsScreen> {
  UploadDestination _destination = uploadDestinationSetting.fallback;
  bool _autoPaste = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(
      AnalyticsService.instance.screen(AnalyticsScreen.fastUploadSettings),
    );
    _load();
  }

  Future<void> _load() async {
    final uploadDestination = uploadDestinationSetting.value;
    final autoPaste = uploadAutoPasteSetting.value;
    if (!mounted) return;
    setState(() {
      _destination = uploadDestination;
      _autoPaste = autoPaste;
      _loading = false;
    });
  }

  Future<void> _onDestinationChanged(UploadDestination destination) async {
    setState(() => _destination = destination);
    await uploadDestinationSetting.set(destination);
  }

  Future<void> _onAutoPasteChanged(bool enabled) async {
    setState(() => _autoPaste = enabled);
    await uploadAutoPasteSetting.set(enabled);
  }

  static String _labelFor(Translations t, UploadDestination destination) =>
      switch (destination) {
        UploadDestination.tmp => t.settings.uploadDestinationTmp,
        UploadDestination.currentDirectory =>
          t.settings.uploadDestinationCurrentDir,
        UploadDestination.ask => t.settings.uploadDestinationAsk,
      };

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final destinationLabels = {
      for (final destination in UploadDestination.values)
        destination: _labelFor(t, destination),
    };
    return LargeTitleScaffold(
      title: t.settings.fastUpload,
      bodyBuilder: (context, scrollController, gutter) => _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space16,
                0,
                AppTheme.space16,
                AppTheme.space32,
              ).add(gutter),
              children: [
                LargeTitleHeader(
                  title: t.settings.fastUpload,
                  subtitle: t.settings.fastUploadSubtitle,
                  padding: const EdgeInsets.only(
                    top: AppTheme.space24,
                    bottom: AppTheme.space8,
                  ),
                ),
                const SizedBox(height: AppTheme.space16),
                AppCard(
                  padding: const EdgeInsets.all(AppTheme.space14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsDropdownField<UploadDestination>(
                        label: t.settings.uploadDestination,
                        value: _destination,
                        labels: destinationLabels,
                        onChanged: _onDestinationChanged,
                      ),
                      const SizedBox(height: AppTheme.space10),
                      Text(
                        switch (_destination) {
                          UploadDestination.tmp =>
                            t.settings.uploadDestinationTmpHint,
                          UploadDestination.currentDirectory =>
                            t.settings.uploadDestinationCurrentDirHint,
                          UploadDestination.ask =>
                            t.settings.uploadDestinationAskHint,
                        },
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.space16),
                AppCard(
                  child: SettingsSwitchTile(
                    title: t.settings.uploadAutoPaste,
                    subtitle: t.settings.uploadAutoPasteSubtitle,
                    value: _autoPaste,
                    onChanged: _onAutoPasteChanged,
                  ),
                ),
              ],
            ),
    );
  }
}
