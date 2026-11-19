import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/pro_source.dart';
import '../../providers/account_provider.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/app/legal_urls.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../../widgets/ui/app_badge.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/clipboard_and_links.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../settings/account_screen.dart';

/// Buying Pro: what it brings, the plans side by side, and one button.
///
/// Flat on the app's own background. Gold is the word Pro alone; the
/// features each carry a colour of their own, and the chosen plan and the
/// button take the app's accent like every other choice and action in it.
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
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ProPaywallScreen(source: source),
      ),
    );
  }

  @override
  ConsumerState<ProPaywallScreen> createState() => _ProPaywallScreenState();
}

class _ProPaywallScreenState extends ConsumerState<ProPaywallScreen> {
  List<ProOffer> _offers = const [];
  ProOffer? _chosen;
  bool _loaded = false;
  bool _busy = false;
  bool _leaving = false;

  /// Whether a store's code was sent off from here, so Pro arriving after
  /// it is thanked for rather than met with "you already have Pro".
  bool _redeeming = false;

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
    final pro = Translations.of(context).account.pro;
    if (_redeeming) {
      AppNotifications.success(context, pro.thanks);
    } else {
      AppNotifications.info(context, pro.already);
    }
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

  /// Takes a store's code for Pro: the App Store's own sheet on iOS, Google
  /// Play's redeem page on Android. Either way the purchase comes back
  /// through the store, and [_leaveIfPro] closes the paywall when it does.
  Future<void> _redeem() async {
    final t = Translations.of(context);
    _capture(AnalyticsEvent.redeemCodeOpened);
    _redeeming = true;
    try {
      await _pro.redeemCode();
    } on ProException catch (error) {
      if (mounted && error.failure != ProFailure.cancelled) {
        AppNotifications.error(context, t.account.pro.failed);
      }
      return;
    } catch (_) {
      if (mounted) AppNotifications.error(context, t.account.pro.failed);
      return;
    }
    if (isAndroidPlatform && mounted) {
      await openExternalUrl(context, Uri.parse(ProService.playRedeemUrl));
    }
  }

  Future<void> _signIn() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen()));
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
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
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
                builder: (context, gutter) => ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space24,
                    0,
                    AppTheme.space24,
                    AppTheme.space24,
                  ).add(gutter),
                  children: [
                    const SizedBox(height: AppTheme.space8),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${p.titleLead} '),
                          TextSpan(
                            text: p.titlePro,
                            style: TextStyle(color: colors.gold),
                          ),
                        ],
                      ),
                      style: text.displayLarge,
                    ),
                    const SizedBox(height: AppTheme.space8),
                    Text(
                      p.tagline,
                      style: text.bodyLarge?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppTheme.space32),
                    _Feature(
                      icon: PhosphorIconsRegular.bellRinging,
                      color: colors.primary,
                      title: p.pushTitle,
                      body: p.pushBody,
                    ),
                    _Feature(
                      icon: PhosphorIconsRegular.arrowsClockwise,
                      color: colors.success,
                      title: p.syncTitle,
                      body: p.syncBody,
                    ),
                    _Feature(
                      icon: PhosphorIconsRegular.heart,
                      color: colors.error,
                      title: p.supportTitle,
                      body: p.supportBody,
                    ),
                  ],
                ),
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
              onRedeem: _pro.canRedeemCode ? _redeem : null,
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
      for (final offer in _offers) ...[
        _PlanTile(
          offer: offer,
          selected: identical(offer, _chosen),
          saving: offer.period == 'annual'
              ? savingPercent(offer, monthly)
              : null,
          onTap: _busy ? null : () => setState(() => _chosen = offer),
        ),
        const SizedBox(height: AppTheme.space10),
      ],
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

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;

  /// Each feature its own colour, so the list reads as three things rather
  /// than one block; gold is kept for the word Pro alone.
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppTheme.icon24, color: color),
          const SizedBox(width: AppTheme.space14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                const SizedBox(height: AppTheme.space4),
                Text(body, style: text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One plan to pick: its name, its price, and for the yearly one what that
/// comes to a month and what it saves. The chosen one takes the accent's
/// outline and a filled radio mark.
class _PlanTile extends StatelessWidget {
  const _PlanTile({
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
    final t = Translations.of(context);
    final p = t.account.pro.paywall;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final (name, price) = switch (offer.period) {
      'annual' => (p.yearly, p.perYear(price: offer.price)),
      'lifetime' => (p.lifetime, offer.price),
      _ => (p.monthly, p.perMonth(price: offer.price)),
    };
    final perMonth = offer.period == 'annual' ? offer.perMonth : null;
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppTheme.interactiveDuration,
          curve: AppTheme.interactiveCurve,
          padding: const EdgeInsets.all(AppTheme.space16),
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: radius,
            border: Border.all(
              color: selected ? colors.primary : colors.surfaceBorder,
              width: selected ? AppTheme.strokeWide : AppTheme.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? PhosphorIconsFill.radioButton
                    : PhosphorIconsRegular.circle,
                size: AppTheme.icon24,
                color: selected ? colors.primary : colors.textTertiary,
              ),
              const SizedBox(width: AppTheme.space14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name, style: text.titleMedium),
                        if (offer.trialDays case final days?) ...[
                          const SizedBox(width: AppTheme.space8),
                          AppBadge(
                            p.trialBadge(days: days),
                            tone: BadgeTone.success,
                          ),
                        ] else if (saving != null) ...[
                          const SizedBox(width: AppTheme.space8),
                          AppBadge(
                            p.save(percent: '$saving'),
                            tone: BadgeTone.success,
                          ),
                        ],
                      ],
                    ),
                    if (perMonth != null) ...[
                      const SizedBox(height: AppTheme.space2),
                      Text(
                        p.yearlyPerMonth(price: perMonth),
                        style: text.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              Text(price, style: text.titleSmall),
            ],
          ),
        ),
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
    this.onRedeem,
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

  /// Takes a store's code for Pro; null where this build cannot.
  final VoidCallback? onRedeem;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final p = t.account.pro.paywall;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final link = text.bodySmall?.copyWith(color: colors.textSecondary);
    return ContentGutter(
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
                if (signedIn && onRedeem != null)
                  TextButton(
                    onPressed: busy ? null : onRedeem,
                    child: Text(t.account.pro.redeem, style: link),
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
            const SizedBox(height: AppTheme.space8),
            Text(
              p.supporter,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
