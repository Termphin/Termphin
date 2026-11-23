import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/assistant/assistant_client.dart';
import '../../services/assistant/assistant_memory.dart';
import '../../services/pro/pro_service.dart';
import '../../services/settings/assistant_settings.dart';
import '../../theme/theme.dart';
import '../../widgets/account/pro_feature_sheet.dart';
import '../../widgets/assistant/phin_badges.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_header.dart';
import '../../widgets/ui/settings_tile.dart';

/// Phin's settings: whether it is there at all, whether it remembers, and
/// what it remembers about each server, note by note, to read and forget.
class PhinSettingsScreen extends ConsumerStatefulWidget {
  const PhinSettingsScreen({super.key});

  @override
  ConsumerState<PhinSettingsScreen> createState() => _PhinSettingsScreenState();
}

class _PhinSettingsScreenState extends ConsumerState<PhinSettingsScreen> {
  Map<String, List<String>> _notes = const {};
  AssistantUsage? _usage;

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.phinSettings));
    assistantMemory.addListener(_reload);
    unawaited(_reload());
    unawaited(_loadUsage());
  }

  Future<void> _loadUsage() async {
    final usage = await HttpAssistantTransport().fetchUsage();
    if (mounted) setState(() => _usage = usage);
  }

  @override
  void dispose() {
    assistantMemory.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final notes = await assistantMemory.all();
    if (mounted) setState(() => _notes = notes);
  }

  Future<void> _forget(String profileId, String name) async {
    final t = Translations.of(context).assistant;
    final sure = await showConfirmDialog(
      context,
      title: t.forgetServer,
      message: t.forgetServerConfirm(name: name),
      confirmLabel: t.forget,
      destructive: true,
    );
    if (sure) await assistantMemory.forget(profileId);
  }

  Future<void> _forgetAll() async {
    final t = Translations.of(context).assistant;
    final sure = await showConfirmDialog(
      context,
      title: t.forgetAll,
      message: t.forgetAllConfirm,
      confirmLabel: t.forget,
      destructive: true,
    );
    if (sure) await assistantMemory.forgetAll();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).assistant;
    final colors = context.colors;
    final profiles = {
      for (final profile in ref.watch(profilesProvider)) profile.id: profile,
    };
    final anonymize = ref.watch(anonymizeProvider);
    String nameOf(String profileId) {
      final profile = profiles[profileId];
      if (profile == null) return t.unknownServer;
      return anonymize ? IdentityAnonymizer.name(profile.id) : profile.name;
    }

    return LargeTitleScaffold(
      title: t.settingsTitle,
      bodyBuilder: (context, scrollController, gutter) => ListenableBuilder(
        listenable: Listenable.merge([
          phinEnabledSetting,
          phinMemorySetting,
          ProService.instance.active,
        ]),
        builder: (context, _) {
          final pro = ProService.instance.active.value;
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space16,
              0,
              AppTheme.space16,
              AppTheme.space32,
            ).add(gutter),
            children: [
              LargeTitleHeader(
                title: t.settingsTitle,
                subtitle: t.settingsSubtitle,
                padding: const EdgeInsets.only(
                  top: AppTheme.space24,
                  bottom: AppTheme.space8,
                ),
              ),
              AppCard.fields(
                children: [
                  SettingsSwitchTile(
                    icon: PhosphorIconsRegular.sparkle,
                    title: t.enable,
                    titleTrailing: const PhinBadges(),
                    subtitle: t.enableSubtitle,
                    value: pro && phinEnabledSetting.value,
                    onChanged: pro
                        ? (on) => unawaited(phinEnabledSetting.set(on))
                        : null,
                  ),
                  const AppDivider(),
                  SettingsSwitchTile(
                    icon: PhosphorIconsRegular.bookmarkSimple,
                    title: t.memory,
                    subtitle: t.memorySubtitle,
                    value: pro && phinMemorySetting.value,
                    onChanged: pro && phinEnabledSetting.value
                        ? (on) => unawaited(phinMemorySetting.set(on))
                        : null,
                  ),
                  const AppDivider(),
                  const HowItWorksTile(feature: ProFeature.phin),
                ],
              ),
              if (_usage case final usage?) ...[
                const SizedBox(height: AppTheme.space24),
                SectionHeader(t.usageTitle),
                const SizedBox(height: AppTheme.space8),
                AppCard(
                  padding: const EdgeInsets.all(AppTheme.space16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.usageUsed(percent: (usage.used * 100).round()),
                        style: TextStyle(
                          fontSize: AppTheme.font15,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppTheme.space10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusPill,
                        ),
                        child: LinearProgressIndicator(
                          value: usage.used,
                          minHeight: AppTheme.space6,
                          color: usage.used >= 0.8
                              ? colors.warning
                              : colors.primary,
                          backgroundColor: colors.surfaceOffset,
                        ),
                      ),
                      const SizedBox(height: AppTheme.space8),
                      Text(
                        t.usageRenews(
                          date: DateFormat.MMMd().format(
                            usage.renews.toLocal(),
                          ),
                        ),
                        style: TextStyle(
                          fontSize: AppTheme.font13,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppTheme.space24),
              SectionHeader(t.knowsTitle),
              const SizedBox(height: AppTheme.space8),
              if (_notes.isEmpty)
                EmptyStateHint(
                  icon: PhosphorIconsRegular.bookmarkSimple,
                  text: t.knowsEmpty,
                )
              else ...[
                for (final entry in _notes.entries) ...[
                  AppCard.fields(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.space16,
                          AppTheme.space12,
                          AppTheme.space4,
                          AppTheme.space4,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                nameOf(entry.key),
                                style: TextStyle(
                                  fontSize: AppTheme.font15,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _forget(entry.key, nameOf(entry.key)),
                              child: Text(t.forget),
                            ),
                          ],
                        ),
                      ),
                      for (final note in entry.value) ...[
                        const AppDivider(),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: AppTheme.space16,
                            right: AppTheme.space4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  note,
                                  style: TextStyle(
                                    fontSize: AppTheme.font14,
                                    height: 1.4,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: t.removeNote,
                                onPressed: () => unawaited(
                                  assistantMemory.remove(entry.key, note),
                                ),
                                icon: Icon(
                                  PhosphorIconsRegular.trash,
                                  size: AppTheme.icon18,
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppTheme.space12),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _forgetAll,
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    child: Text(t.forgetAll),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
