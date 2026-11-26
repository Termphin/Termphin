import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings/assistant_settings.dart';
import '../../theme/theme.dart';
import '../../widgets/account/live_status_card.dart';
import '../../widgets/account/pro_feature_sheet.dart';
import '../../widgets/account/sync_card.dart';
import '../../widgets/pro/ascii_glow.dart';
import '../../widgets/pro/pro_benefits.dart';
import '../../widgets/settings/notifications_settings_section.dart';
import '../../widgets/settings/pro_devices_list.dart';
import '../../widgets/ui/app_badge.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/settings_tile.dart';
import '../settings/phin_settings_screen.dart';

/// Everything Termphin Pro adds, for an account that has it, dressed like
/// the paywall that sold it: the same glow at the top, "Termphin Pro" and
/// that it is active, then each feature the way the paywall described it -
/// Phin, notifications with Termphin closed, live status and sync - with
/// its controls right under it.
///
/// Live status lives only here. The others also live where they always
/// did - notifications in Settings, sync on the account page, Phin in its
/// own settings - and the controls here are the same ones, so this is where
/// to see and tune all of Pro at once. Only what Pro adds: of notifications
/// the switch for when the app is closed, and not the subscription, which
/// the account page keeps.
class ProFeaturesScreen extends StatefulWidget {
  const ProFeaturesScreen({super.key, this.appVersion});

  /// For the "New" badge on the notifications switch.
  final String? appVersion;

  @override
  State<ProFeaturesScreen> createState() => _ProFeaturesScreenState();
}

class _ProFeaturesScreenState extends State<ProFeaturesScreen> {
  final _glow = GlobalKey<AsciiGlowState>();

  /// The headline sits at the foot of the glow, like the paywall's.
  static const _headlineAt = Alignment(0, 0.55);

  /// The column the paywall reads in, so the two look like one place.
  static const _columnWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final hub = t.proHub;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary.invisible,
        shape: const Border(),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: ContentGutter(
          maxWidth: _columnWidth,
          onlyWide: false,
          builder: (context, gutter) {
            final sides = const EdgeInsets.symmetric(
              horizontal: AppTheme.space16,
            ).add(gutter);
            return ListView(
              padding: const EdgeInsets.only(bottom: AppTheme.space32),
              children: [
                Listener(
                  onPointerDown: (event) =>
                      _glow.currentState?.touch(event.localPosition),
                  onPointerMove: (event) =>
                      _glow.currentState?.touch(event.localPosition),
                  child: SizedBox(
                    height: AsciiGlow.headerHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AsciiGlow(
                              key: _glow,
                              quietAround: _headlineAt,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                hub.title,
                                textAlign: TextAlign.center,
                                style: text.displayLarge?.copyWith(
                                  fontFamily: AppTheme.displayFamily,
                                  fontSize: AppTheme.font40,
                                  height: 1.1,
                                  letterSpacing: -0.5,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: AppTheme.space10),
                              AppBadge(hub.active, tone: BadgeTone.pro),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.space24),
                Padding(
                  padding: sides,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final benefit in ProBenefit.values)
                        _Section(
                          benefit: benefit,
                          child: _controls(benefit, t),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The switches and links under [benefit] - what to tune of it here.
  Widget _controls(ProBenefit benefit, Translations t) => switch (benefit) {
    ProBenefit.phin => ListenableBuilder(
      listenable: phinEnabledSetting,
      builder: (context, _) => AppCard.fields(
        children: [
          SettingsSwitchTile(
            icon: PhosphorIconsRegular.sparkle,
            title: t.assistant.enable,
            subtitle: t.assistant.enableSubtitle,
            value: phinEnabledSetting.value,
            onChanged: (on) => unawaited(phinEnabledSetting.set(on)),
          ),
          const AppDivider(),
          SettingsTile(
            icon: PhosphorIconsRegular.slidersHorizontal,
            title: t.proHub.phinSettings,
            subtitle: t.proHub.phinSettingsSubtitle,
            destination: () => const PhinSettingsScreen(),
          ),
          const AppDivider(),
          const HowItWorksTile(feature: ProFeature.phin),
        ],
      ),
    ),
    ProBenefit.notifications => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard.fields(
          children: [
            NotifyWhenClosedTiles(
              appVersion: widget.appVersion,
              divided: false,
              icon: PhosphorIconsRegular.bellRinging,
            ),
          ],
        ),
        const ProDevicesList(),
      ],
    ),
    ProBenefit.liveStatus => const LiveStatusCard(),
    ProBenefit.sync => const SyncCard(),
  };
}

/// One Pro benefit: said the way the paywall says it, with its controls
/// right under it.
class _Section extends StatelessWidget {
  const _Section({required this.benefit, required this.child});

  final ProBenefit benefit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space8),
            child: ProBenefitRow(benefit: benefit),
          ),
          const SizedBox(height: AppTheme.space12),
          child,
        ],
      ),
    );
  }
}
