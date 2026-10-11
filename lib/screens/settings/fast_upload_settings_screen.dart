import 'dart:async';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/settings/upload_settings.dart';
import '../../theme/theme.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_dropdown.dart';
import '../../widgets/ui/large_title_scaffold.dart';
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

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return LargeTitleScaffold(
      title: t.settings.fastUpload,
      bodyBuilder: (context, scrollController, gutter) => _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32).add(gutter),
              children: [
                LargeTitleHeader(
                  title: t.settings.fastUpload,
                  subtitle: t.settings.fastUploadSubtitle,
                  padding: const EdgeInsets.only(top: 24, bottom: 8),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.settings.uploadDestination,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        _UploadDestinationDropdown(
                          value: _destination,
                          onChanged: _onDestinationChanged,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          switch (_destination) {
                            UploadDestination.tmp =>
                              t.settings.uploadDestinationTmpHint,
                            UploadDestination.currentDirectory =>
                              t.settings.uploadDestinationCurrentDirHint,
                            UploadDestination.ask =>
                              t.settings.uploadDestinationAskHint,
                          },
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.colors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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

class _UploadDestinationDropdown extends StatelessWidget {
  const _UploadDestinationDropdown({
    required this.value,
    required this.onChanged,
  });

  final UploadDestination value;
  final ValueChanged<UploadDestination> onChanged;

  String _labelFor(Translations t, UploadDestination destination) =>
      switch (destination) {
        UploadDestination.tmp => t.settings.uploadDestinationTmp,
        UploadDestination.currentDirectory =>
          t.settings.uploadDestinationCurrentDir,
        UploadDestination.ask => t.settings.uploadDestinationAsk,
      };

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return DropdownButton2<UploadDestination>(
      valueListenable: ValueNotifier(value),
      isExpanded: true,
      underline: const SizedBox.shrink(),
      selectedItemBuilder: (context) => UploadDestination.values
          .map(
            (destination) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _labelFor(t, destination),
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (destination) {
        if (destination != null) onChanged(destination);
      },
      buttonStyleData: ButtonStyleData(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.fieldFill,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: context.colors.surfaceBorder),
        ),
        elevation: 0,
      ),
      iconStyleData: IconStyleData(
        icon: Icon(
          PhosphorIconsFill.caretDown,
          size: 16,
          color: context.colors.textTertiary,
        ),
        iconSize: 16,
      ),
      dropdownStyleData: appDropdownStyle(context),
      menuItemStyleData: appDropdownItemStyle(
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      items: UploadDestination.values
          .map(
            (destination) => DropdownItem<UploadDestination>(
              value: destination,
              intrinsicHeight: true,
              child: AppDropdownItem(
                label: _labelFor(t, destination),
                selected: destination == value,
              ),
            ),
          )
          .toList(),
    );
  }
}
