import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/pro_source.dart';
import '../../screens/pro/pro_paywall_screen.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../pro/ascii_glow.dart';
import '../pro/feature_demos.dart';
import '../ui/app_badge.dart';
import '../ui/app_sheet.dart';
import '../ui/modal_actions.dart';
import '../ui/settings_tile.dart';

/// The features a row in Settings can point at as needing Pro.
enum ProFeature {
  notifications(ProSource.settingsNotifications),
  liveStatus(ProSource.liveStatus);

  const ProFeature(this.source);

  /// Where the user was when the paywall was opened from this feature.
  final ProSource source;
}

/// The gold "Pro" pill beside a row that needs Pro. Tapping it explains the
/// feature in a sheet and never opens the checkout; it is gone once the
/// account has Pro.
class ProFeatureChip extends StatelessWidget {
  const ProFeatureChip({super.key, required this.feature});

  final ProFeature feature;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: ProService.instance.active,
      builder: (context, pro, _) {
        if (pro) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showProFeatureSheet(context, feature),
          child: AppBadge(t.account.pro.badge, tone: BadgeTone.pro),
        );
      },
    );
  }
}

/// Opens the explanation of [feature] as a sheet.
///
/// [offerPro] off leaves out the way to the paywall, for a sheet opened from
/// the paywall itself.
Future<void> showProFeatureSheet(
  BuildContext context,
  ProFeature feature, {
  bool offerPro = true,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) => ProFeatureSheet(
      feature: feature,
      paywallContext: context,
      offerPro: offerPro,
    ),
  );
}

/// What a Pro feature does: two cards users can swipe or step through - the
/// feature's own phone demo first, then the AI agent alerts/live-status
/// card - with a way to the paywall for an account without Pro.
///
/// [paywallContext] is the screen the sheet was opened from: the sheet is
/// gone by the time the paywall opens, so the paywall is pushed from there.
class ProFeatureSheet extends StatefulWidget {
  const ProFeatureSheet({
    super.key,
    required this.feature,
    required this.paywallContext,
    this.offerPro = true,
  });

  final ProFeature feature;
  final BuildContext paywallContext;

  /// Whether an account without Pro is offered the way to the paywall.
  final bool offerPro;

  @override
  State<ProFeatureSheet> createState() => _ProFeatureSheetState();
}

class _ProFeatureSheetState extends State<ProFeatureSheet> {
  static const _pageCount = 2;
  int _page = 0;
  int _direction = 1;

  void _goTo(int next) {
    final clamped = next.clamp(0, _pageCount - 1);
    if (clamped == _page) return;
    setState(() {
      _direction = clamped > _page ? 1 : -1;
      _page = clamped;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final (primaryTitle, primaryBody, primaryDemo) = switch (widget.feature) {
      ProFeature.notifications => (
        t.proFeature.notificationsTitle,
        t.proFeature.notificationsBody,
        const FeatureDemo(kind: FeatureDemoKind.notifications) as Widget,
      ),
      ProFeature.liveStatus => (
        t.proFeature.liveTitle,
        t.proFeature.liveBody,
        const FeatureDemo(kind: FeatureDemoKind.live) as Widget,
      ),
    };
    final card = switch (_page) {
      0 => _FeatureCard(
        key: ValueKey('proFeaturePage-0-${widget.feature.name}'),
        media: primaryDemo,
        title: primaryTitle,
        body: primaryBody,
      ),
      _ => _FeatureCard(
        key: ValueKey('proFeaturePage-1-${widget.feature.name}'),
        media: const _AiAgentsShowcase(),
        title: t.proFeature.aiAgentsTitle,
        body: t.proFeature.aiAgentsBody,
      ),
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space16,
          AppTheme.space20,
          AppTheme.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final vx = details.primaryVelocity ?? 0;
                if (vx < -200) {
                  _goTo(_page + 1);
                } else if (vx > 200) {
                  _goTo(_page - 1);
                }
              },
              child: AnimatedSize(
                duration: AppTheme.motionFast,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: AppTheme.motionFast,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final offset = Tween<Offset>(
                      begin: Offset(_direction * 0.08, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: offset, child: child),
                    );
                  },
                  child: card,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.space14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  key: const ValueKey('proFeaturePrev'),
                  visualDensity: VisualDensity.compact,
                  onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                  icon: Icon(
                    PhosphorIconsRegular.caretLeft,
                    size: AppTheme.icon16,
                    color: _page > 0
                        ? colors.textSecondary
                        : colors.textTertiary,
                  ),
                ),
                for (var i = 0; i < _pageCount; i++)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _goTo(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space2,
                        vertical: AppTheme.space6,
                      ),
                      child: AnimatedContainer(
                        duration: AppTheme.interactiveDuration,
                        curve: Curves.easeOut,
                        height: 6,
                        width: i == _page ? 18 : 6,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? colors.primary
                              : colors.surfaceBorderStrong,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  key: const ValueKey('proFeatureNext'),
                  visualDensity: VisualDensity.compact,
                  onPressed: _page < _pageCount - 1
                      ? () => _goTo(_page + 1)
                      : null,
                  icon: Icon(
                    PhosphorIconsRegular.caretRight,
                    size: AppTheme.icon16,
                    color: _page < _pageCount - 1
                        ? colors.textSecondary
                        : colors.textTertiary,
                  ),
                ),
              ],
            ),
            if (widget.offerPro && !ProService.instance.active.value) ...[
              const SizedBox(height: AppTheme.space12),
              ModalActions(
                primary: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(AppTheme.space48),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(
                      ProPaywallScreen.show(
                        widget.paywallContext,
                        source: widget.feature.source,
                      ),
                    );
                  },
                  child: Text(t.proFeature.seePro),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    super.key,
    required this.media,
    required this.title,
    required this.body,
  });

  final Widget media;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: media),
        const SizedBox(height: AppTheme.space20),
        Text(title, style: text.titleMedium),
        const SizedBox(height: AppTheme.space12),
        Text(
          body,
          style: text.bodyMedium?.copyWith(color: context.colors.textSecondary),
        ),
      ],
    );
  }
}

/// The AI coding agents showcase card from What's New, framed over the ASCII
/// glow so both pages in [ProFeatureSheet] carry the same visual weight.
class _AiAgentsShowcase extends StatelessWidget {
  const _AiAgentsShowcase();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.surfaceBorder),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: IgnorePointer(child: AsciiGlow())),
            Padding(
              padding: const EdgeInsets.all(AppTheme.space16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: AspectRatio(
                  aspectRatio: 16 / 7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: Image.asset(
                      'assets/whats_new/ai-agents.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The row under a Pro feature's switch that opens its demo in the sheet.
class HowItWorksTile extends StatelessWidget {
  const HowItWorksTile({super.key, required this.feature});

  final ProFeature feature;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      key: ValueKey('howItWorks-${feature.name}'),
      icon: PhosphorIconsRegular.playCircle,
      title: Translations.of(context).proFeature.howItWorks,
      onTap: () => unawaited(showProFeatureSheet(context, feature)),
    );
  }
}
