import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/pro_source.dart';
import '../../providers/account_provider.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/app/legal_urls.dart';
import '../../services/app/project_urls.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../../widgets/account/pro_feature_sheet.dart';
import '../../widgets/pro/ascii_glow.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/app_sheet.dart';
import '../../widgets/ui/clipboard_and_links.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_navigator.dart';
import '../settings/account_screen.dart';

/// Buying Pro: what it brings, the plans side by side, and one button.
///
/// One headline over a glow drawn in ASCII at the top, the features listed
/// one under another, and the chosen plan and the button in the app's
/// accent like every other choice and action in it.
/// The yearly plan is chosen to begin with and carries what it saves
/// against twelve months.
///
/// A signed-out visitor sees the same screen with the button turned into
/// "Sign in to continue", since a purchase belongs to an account. Opening it
/// with Pro already on, or finishing a purchase, closes it.
class ProPaywallScreen extends ConsumerStatefulWidget {
  const ProPaywallScreen({
    super.key,
    this.source,
    @visibleForTesting this.offers,
  });

  /// Where the paywall was opened from, carried onto every funnel event it
  /// sends so a purchase can be put down to the place that sold it.
  final ProSource? source;

  /// Stands in for the store's offers in tests, as if they had loaded.
  final List<ProOffer>? offers;

  /// Opens the paywall over whatever is showing, noting [source] - where
  /// the user was - for the funnel.
  static Future<void> show(BuildContext context, {required ProSource source}) {
    unawaited(
      AnalyticsService.instance.capture(
        AnalyticsEvent.paywallViewed,
        properties: {AnalyticsProperty.source: source.id},
      ),
    );
    return pushAppForm<void>(
      context,
      builder: (_) => ProPaywallScreen(source: source),
    );
  }

  @override
  ConsumerState<ProPaywallScreen> createState() => _ProPaywallScreenState();
}

class _ProPaywallScreenState extends ConsumerState<ProPaywallScreen> {
  final _glow = GlobalKey<AsciiGlowState>();

  /// The headline sits at the foot of the glow, clear of the close button
  /// and straight above the features; the glow dims around its middle.
  static const _headlineAt = Alignment(0, 0.55);
  List<ProOffer> _offers = const [];

  /// The longest free trial any plan here offers, for the line under the
  /// title; null when none does.
  int? get _trialDays => _offers
      .map((offer) => offer.trialDays)
      .whereType<int>()
      .fold<int?>(null, (longest, days) => max(longest ?? 0, days));
  ProOffer? _chosen;
  bool _loaded = false;
  bool _busy = false;
  bool _leaving = false;

  ProService get _pro => ProService.instance;

  bool get _canSell => widget.offers != null || _pro.available;

  @override
  void initState() {
    super.initState();
    _pro.active.addListener(_leaveIfPro);
    unawaited(_load());
    unawaited(_checkPro());
  }

  @override
  void dispose() {
    _pro.active.removeListener(_leaveIfPro);
    super.dispose();
  }

  /// Someone who already has Pro is never sold it again: the paywall checks
  /// with the store as it opens, and closes once Pro is known to be on the
  /// account - at opening, or when signing in brings it.
  Future<void> _checkPro() async {
    await _pro.refresh();
    if (mounted) _leaveIfPro();
  }

  /// Closes the paywall, saying so, once Pro is on. A purchase or restore
  /// in flight closes itself instead, when it has a thanks to give.
  void _leaveIfPro() {
    if (_leaving || _busy || !mounted || !_pro.active.value) return;
    _leaving = true;
    AppNotifications.info(
      context,
      Translations.of(context).account.pro.already,
    );
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  /// What every funnel event from this paywall carries: where it was
  /// opened from, plus [extra].
  void _capture(
    AnalyticsEvent event, [
    Map<AnalyticsProperty, Object> extra = const {},
  ]) {
    final source = widget.source;
    unawaited(
      AnalyticsService.instance.capture(
        event,
        properties: {AnalyticsProperty.source: ?source?.id, ...extra},
      ),
    );
  }

  Future<void> _load() async {
    if (_loaded) setState(() => _loaded = false);
    List<ProOffer> offers = const [];
    var failed = false;
    try {
      offers = sortedOffers(widget.offers ?? await _pro.offers());
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    if (offers.isEmpty) {
      _capture(AnalyticsEvent.paywallOffersFailed, {
        AnalyticsProperty.reason: ref.read(accountProvider) == null
            ? 'not_signed_in'
            : failed
            ? 'error'
            : 'none',
      });
    }
    setState(() {
      _offers = offers;
      _chosen = offers.isEmpty ? null : offers.first;
      _loaded = true;
    });
  }

  /// Runs a purchase or restore. [failed] hears why one did not go through,
  /// as the store's own reason or `failed` for anything else.
  Future<void> _attempt(
    Future<void> Function() action, {
    required void Function(String reason) failed,
  }) async {
    final t = Translations.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (_pro.active.value) {
        AppNotifications.success(context, t.account.pro.thanks);
        Navigator.of(context).pop();
        return;
      }
    } on ProException catch (error) {
      failed(analyticsName(error.failure));
      if (mounted && error.failure != ProFailure.cancelled) {
        AppNotifications.error(context, t.account.pro.failed);
      }
    } catch (_) {
      failed('failed');
      if (mounted) AppNotifications.error(context, t.account.pro.failed);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _buy(ProOffer offer) async {
    final plan = {AnalyticsProperty.plan: offer.period};
    _capture(AnalyticsEvent.purchaseStarted, plan);
    await _attempt(
      () async {
        await _pro.buy(offer);
        if (_pro.active.value) {
          _capture(AnalyticsEvent.purchaseCompleted, plan);
        }
      },
      failed: (reason) => _capture(AnalyticsEvent.purchaseFailed, {
        ...plan,
        AnalyticsProperty.reason: reason,
      }),
    );
  }

  /// Restores what the store has for this account. Finding none says so,
  /// since the screen would otherwise look as if nothing happened.
  Future<void> _restore() => _attempt(
    () async {
      await _pro.restore();
      _capture(AnalyticsEvent.restoreFinished, {
        AnalyticsProperty.outcome: _pro.active.value ? 'found' : 'none',
      });
      if (mounted && !_pro.active.value) {
        AppNotifications.info(
          context,
          Translations.of(context).account.pro.paywall.nothingToRestore,
        );
      }
    },
    failed: (reason) => _capture(AnalyticsEvent.restoreFinished, {
      AnalyticsProperty.outcome: 'failed',
      AnalyticsProperty.reason: reason,
    }),
  );

  Future<void> _signIn() async {
    await pushAppPage<void>(
      context,
      window: true,
      title: Translations.of(context).account.title,
      builder: (_) => const AccountScreen(),
    );
    if (!mounted) return;
    if (ref.read(accountProvider) != null) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final p = t.account.pro.paywall;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final signedIn = ref.watch(accountProvider) != null;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary.invisible,
        shape: const Border(),
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: p.close,
            icon: const Icon(PhosphorIconsRegular.x),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ContentGutter(
                maxWidth: _columnWidth,
                onlyWide: false,
                builder: (context, gutter) {
                  final sides = const EdgeInsets.symmetric(
                    horizontal: AppTheme.space24,
                  ).add(gutter);
                  return ListView(
                    padding: const EdgeInsets.only(bottom: AppTheme.space24),
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
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.space24,
                                  ),
                                  child: Text(
                                    switch (_trialDays) {
                                      final days? => p.trialHero(days: days),
                                      null => p.tagline,
                                    },
                                    key: const ValueKey('paywallHeadline'),
                                    textAlign: TextAlign.center,
                                    style: text.displayLarge?.copyWith(
                                      fontFamily: AppTheme.displayFamily,
                                      fontSize: AppTheme.font40,
                                      height: 1.1,
                                      letterSpacing: -0.5,
                                      color: colors.textPrimary,
                                    ),
                                  ),
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
                          children: [
                            _Feature(
                              icon: PhosphorIconsRegular.sparkle,
                              title: p.phinTitle,
                              body: p.phinBody,
                              demo: ProFeature.phin,
                            ),
                            _Feature(
                              icon: PhosphorIconsRegular.bellRinging,
                              title: p.pushTitle,
                              body: p.pushBody,
                              demo: ProFeature.notifications,
                            ),
                            _Feature(
                              icon: PhosphorIconsRegular.pulse,
                              title: p.liveTitle,
                              body: p.liveBody,
                              demo: ProFeature.liveStatus,
                            ),
                            _Feature(
                              icon: PhosphorIconsRegular.arrowsClockwise,
                              title: p.syncTitle,
                              body: p.syncBody,
                            ),
                            _Feature(
                              icon: PhosphorIconsRegular.heart,
                              title: p.supportTitle,
                              body: p.supportBody,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            _Footer(
              plans: _plans(context, t, signedIn: signedIn),
              busy: _busy,
              signedIn: signedIn,
              chosen: _chosen,
              canBuy: _chosen != null && _canSell,
              onBuy: () {
                final chosen = _chosen;
                if (chosen != null) _buy(chosen);
              },
              onSignIn: _signIn,
              onRestore: _restore,
            ),
          ],
        ),
      ),
    );
  }

  /// The plans to pick from. Signed out there are none to show - the store
  /// is asked only for an account - and that is said as what it is rather
  /// than as prices failing to load.
  List<Widget> _plans(
    BuildContext context,
    Translations t, {
    required bool signedIn,
  }) {
    final p = t.account.pro.paywall;
    final text = Theme.of(context).textTheme;
    if (!_canSell && platformHas(PlatformFeature.webAccountLinks)) {
      return [
        Text(
          t.account.pro.buyOnWebBody,
          style: text.bodyMedium?.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: AppTheme.space16),
        FilledButton(
          key: const ValueKey('paywallBuyOnWeb'),
          onPressed: () => unawaited(
            openExternalUrl(
              context,
              Uri.parse('${ProjectUrls.accountPage}/#/plan'),
            ),
          ),
          child: Text(t.account.pro.buyOnWeb),
        ),
      ];
    }
    if (!_canSell) {
      return [Text(t.account.pro.unavailable, style: text.bodyMedium)];
    }
    if (!_loaded) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppTheme.space16),
          child: Center(
            child: CircularProgressIndicator(strokeWidth: AppTheme.strokeWide),
          ),
        ),
      ];
    }
    if (_offers.isEmpty && !signedIn) {
      return [
        Text(p.signInForPrices, style: text.bodyMedium),
        const SizedBox(height: AppTheme.space10),
      ];
    }
    if (_offers.isEmpty) {
      return [
        Text(p.noOffers, style: text.bodyMedium),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : _load,
            child: Text(p.retry),
          ),
        ),
      ];
    }
    final monthly = _offers.where((o) => o.period == 'monthly').firstOrNull;
    return [
      _PlanCards(
        offers: _offers,
        chosen: _chosen,
        saving: (offer) =>
            offer.period == 'annual' ? savingPercent(offer, monthly) : null,
        onPick: _busy ? null : (offer) => setState(() => _chosen = offer),
      ),
      const SizedBox(height: AppTheme.space16),
    ];
  }
}

/// Yearly first, then monthly, then anything else.
@visibleForTesting
List<ProOffer> sortedOffers(List<ProOffer> offers) {
  int rank(String period) => switch (period) {
    'annual' => 0,
    'monthly' => 1,
    _ => 2,
  };
  return [...offers]..sort((a, b) => rank(a.period).compareTo(rank(b.period)));
}

/// How much [yearly] saves against paying [monthly] twelve times, in whole
/// percent, or null when there is nothing worth saying.
@visibleForTesting
int? savingPercent(ProOffer yearly, ProOffer? monthly) {
  final year = yearly.amount;
  final month = monthly?.amount;
  if (year == null || month == null || month <= 0) return null;
  final percent = ((1 - year / (month * 12)) * 100).floor();
  return percent >= 5 ? percent : null;
}

/// One thing Pro adds: its icon, its name and a line on it, and for a
/// feature with a demo a link to how it works, which opens the demo's sheet
/// over the paywall.
/// The widest the features, plans and buttons run, upright on a tablet as
/// well as on its side: wider, the two plan cards and the button under them
/// stretch into bars.
const double _columnWidth = 480;

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.body,
    this.demo,
  });

  final IconData icon;
  final String title;
  final String body;
  final ProFeature? demo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final demo = this.demo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppTheme.icon20, color: colors.textSecondary),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: AppTheme.space2),
                Text(
                  body,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                if (demo != null)
                  TextButton.icon(
                    key: ValueKey('paywallHowItWorks-${demo.name}'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTheme.space6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      foregroundColor: colors.primary,
                      textStyle: text.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(
                      PhosphorIconsRegular.playCircle,
                      size: AppTheme.icon16,
                    ),
                    label: Text(Translations.of(context).proFeature.howItWorks),
                    onPressed: () => unawaited(
                      showProFeatureSheet(context, demo, offerPro: false),
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

/// The plans side by side as cards of equal height, monthly first so the
/// yearly one sits under the thumb: its name, its price large with the
/// period small beside it, and a line under that. The chosen card takes a
/// tint of the accent and an accent edge; the yearly one wears what it
/// saves as a tilted tag on its corner.
class _PlanCards extends StatelessWidget {
  const _PlanCards({
    required this.offers,
    required this.chosen,
    required this.saving,
    required this.onPick,
  });

  final List<ProOffer> offers;
  final ProOffer? chosen;
  final int? Function(ProOffer offer) saving;
  final ValueChanged<ProOffer>? onPick;

  /// Monthly, then yearly, then anything else.
  static List<ProOffer> _shown(List<ProOffer> offers) {
    int rank(String period) => switch (period) {
      'monthly' => 0,
      'annual' => 1,
      _ => 2,
    };
    return [...offers]
      ..sort((a, b) => rank(a.period).compareTo(rank(b.period)));
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown(offers);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, offer) in shown.indexed) ...[
            if (i > 0) const SizedBox(width: AppTheme.space10),
            Expanded(
              child: _PlanCard(
                offer: offer,
                selected: identical(offer, chosen),
                saving: saving(offer),
                onTap: onPick == null ? null : () => onPick!(offer),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.offer,
    required this.selected,
    required this.saving,
    required this.onTap,
  });

  final ProOffer offer;
  final bool selected;
  final int? saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Translations.of(context).account.pro.paywall;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    final (name, suffix) = switch (offer.period) {
      'annual' => (p.yearly, p.perYearShort),
      'lifetime' => (p.lifetime, null),
      _ => (p.monthly, p.perMonthShort),
    };
    final detail = switch (offer.period) {
      'annual' => switch (offer.perMonth) {
        final perMonth? => p.perMonthCompact(price: perMonth),
        null => null,
      },
      'monthly' => p.billedMonthly,
      _ => null,
    };
    return Semantics(
      selected: selected,
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: AnimatedContainer(
                  duration: AppTheme.interactiveDuration,
                  curve: AppTheme.interactiveCurve,
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primary.withValues(alpha: 0.14)
                        : colors.surfaceCard,
                    borderRadius: radius,
                    border: Border.all(
                      color: selected
                          ? colors.primary.withValues(alpha: 0.7)
                          : colors.surfaceCard,
                      width: AppTheme.strokeWide,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: offer.price,
                          style: text.titleLarge?.copyWith(
                            fontSize: AppTheme.font26,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (suffix != null)
                          TextSpan(
                            text: suffix,
                            style: text.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AppTheme.space4),
                    Text(
                      detail,
                      style: text.bodySmall?.copyWith(
                        color: selected ? colors.primary : colors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (saving case final percent?)
            Positioned(
              top: -AppTheme.space10,
              right: AppTheme.space10,
              child: Transform.rotate(
                angle: 0.12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space8,
                    vertical: AppTheme.space2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.success,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                  ),
                  child: Text(
                    p.saveShort(percent: '$percent'),
                    style: text.labelSmall?.copyWith(
                      color: colors.backgroundPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The plans, the button, the restore link and the small print, pinned
/// under the scrolling part so the choice and the purchase never scroll
/// away.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.plans,
    required this.busy,
    required this.signedIn,
    required this.chosen,
    required this.canBuy,
    required this.onBuy,
    required this.onSignIn,
    required this.onRestore,
  });

  /// The plans to pick from, kept right above the button so the choice and
  /// the purchase are read together and neither scrolls away.
  final List<Widget> plans;
  final bool busy;
  final bool signedIn;

  /// The plan picked, whose trial and price the button and the small print
  /// state.
  final ProOffer? chosen;
  final bool canBuy;
  final VoidCallback onBuy;
  final VoidCallback onSignIn;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final p = t.account.pro.paywall;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final link = text.bodySmall?.copyWith(color: colors.textSecondary);
    return ContentGutter(
      maxWidth: _columnWidth,
      onlyWide: false,
      builder: (context, gutter) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space24,
          AppTheme.space8,
          AppTheme.space24,
          AppTheme.space8,
        ).add(gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...plans,
            const SizedBox(height: AppTheme.space4),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(AppTheme.space48),
              ),
              onPressed: busy
                  ? null
                  : signedIn
                  ? (canBuy ? onBuy : null)
                  : onSignIn,
              child: busy
                  ? SizedBox.square(
                      dimension: AppTheme.icon20,
                      child: CircularProgressIndicator(
                        strokeWidth: AppTheme.strokeWide,
                        color: colors.onPrimary,
                      ),
                    )
                  : Text(
                      !signedIn
                          ? p.signInFirst
                          : chosen?.trialDays != null
                          ? p.startTrial(days: chosen!.trialDays!)
                          : p.subscribe,
                    ),
            ),
            const SizedBox(height: AppTheme.space4),
            if (chosen case ProOffer(
              trialDays: final days?,
              :final price,
              :final period,
            ))
              Text(
                p.trialTerms(
                  days: days,
                  price: period == 'annual'
                      ? p.perYear(price: price)
                      : p.perMonth(price: price),
                ),
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            Text(p.legal, style: text.bodySmall, textAlign: TextAlign.center),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                if (signedIn)
                  TextButton(
                    onPressed: busy ? null : onRestore,
                    child: Text(t.account.pro.restore, style: link),
                  ),
                TextButton(
                  onPressed: () => openExternalUrl(
                    context,
                    Uri.parse(LegalUrls.termsOfService),
                  ),
                  child: Text(p.terms, style: link),
                ),
                TextButton(
                  onPressed: () => openExternalUrl(
                    context,
                    Uri.parse(LegalUrls.privacyPolicy),
                  ),
                  child: Text(p.privacy, style: link),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
