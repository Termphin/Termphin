import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/strings.g.dart';
import '../../screens/pro/pro_features_screen.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../ui/app_badge.dart';
import '../ui/modal_actions.dart';
import '../ui/section_navigator.dart';
import 'ascii_glow.dart';
import 'pro_benefits.dart';

/// The welcome shown once Pro is on an account for the first time on this
/// device, however it got there: bought in the app, restored, redeemed, or
/// bought on the web and picked up on the next refresh - as long as the
/// store says it began within [freshFor]. Without the store's word (on a
/// computer) it waits rather than guess.
///
/// Waits for the launch's own interstitials ([ready]) and for a paywall to
/// close ([hold]/[release]), so it never stacks on another dialog nor lands
/// under a route that is about to pop.
class ProWelcome {
  ProWelcome._();

  /// Set once the welcome has been shown on this device, or once Pro turned
  /// out to be older than [freshFor].
  static const prefsKey = 'pro_welcomed';

  /// How new Pro has to be to be welcomed. A purchase in the app is welcomed
  /// as the paywall closes; one on the web or a code reaches the app on its
  /// next refresh, well inside this. Pro older than that - an account that
  /// had it before this welcome existed - is marked welcomed without it.
  static const freshFor = Duration(days: 1);

  /// The navigator's context the welcome opens in, set by the app.
  static BuildContext? Function()? host;

  static int _held = 0;
  static bool _ready = false;
  static bool _showing = false;

  /// Keeps the welcome back while a paywall is open.
  static void hold() => _held++;

  /// The paywall is gone: the welcome may come now.
  static void release() {
    if (_held > 0) _held--;
    unawaited(maybeShow());
  }

  /// The launch's interstitials are done.
  static void ready() {
    _ready = true;
    unawaited(maybeShow());
  }

  @visibleForTesting
  static void resetForTest() {
    _held = 0;
    _ready = false;
    _showing = false;
    host = null;
  }

  /// Shows the welcome if Pro is on and it has not been shown here yet.
  static Future<void> maybeShow() async {
    if (_held > 0 || !_ready || _showing) return;
    if (!ProService.instance.active.value) return;
    final since = ProService.instance.since.value;
    if (since == null) return;
    _showing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(prefsKey) ?? false) return;
      if (DateTime.now().difference(since) > freshFor) {
        await prefs.setBool(prefsKey, true);
        return;
      }
      final context = host?.call();
      if (context == null || !context.mounted) return;
      if (_held > 0 || !ProService.instance.active.value) return;
      await prefs.setBool(prefsKey, true);
      if (!context.mounted) return;
      await showProWelcomeDialog(context);
    } finally {
      _showing = false;
    }
  }
}

/// Shows the welcome to Pro, with everything it adds.
Future<void> showProWelcomeDialog(BuildContext context) => showDialog<void>(
  context: context,
  animationStyle: AppTheme.popUpAnimation,
  builder: (_) => const ProWelcomeDialog(),
);

/// "Welcome to Pro" over the paywall's glow, a thank-you, each feature as the
/// paywall described it, and a way straight to where they are switched on.
class ProWelcomeDialog extends StatelessWidget {
  const ProWelcomeDialog({super.key});

  /// Where the headline sits in the glow, kept quiet behind it.
  static const _headlineAt = Alignment(0, 0.45);

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: colors.surfaceElevated,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space24,
        vertical: AppTheme.space40,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: colors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 150,
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: AsciiGlow(quietAround: _headlineAt),
                            ),
                          ),
                          Align(
                            alignment: _headlineAt,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppBadge(t.proHub.title, tone: BadgeTone.pro),
                                const SizedBox(height: AppTheme.space8),
                                Text(
                                  t.proWelcome.title,
                                  key: const ValueKey('proWelcomeTitle'),
                                  textAlign: TextAlign.center,
                                  style: text.displayLarge?.copyWith(
                                    fontFamily: AppTheme.displayFamily,
                                    fontSize: AppTheme.font30,
                                    height: 1.1,
                                    letterSpacing: -0.5,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.space20,
                        AppTheme.space12,
                        AppTheme.space20,
                        AppTheme.space4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            t.proWelcome.body,
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: AppTheme.space20),
                          for (final benefit in ProBenefit.values)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppTheme.space16,
                              ),
                              child: ProBenefitRow(benefit: benefit),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space20,
                AppTheme.space8,
                AppTheme.space20,
                AppTheme.space20,
              ),
              child: ModalActions(
                primary: FilledButton(
                  key: const ValueKey('proWelcomeSetUp'),
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    final host = navigator.context;
                    navigator.pop();
                    unawaited(
                      pushAppPage<void>(
                        host,
                        title: t.proHub.title,
                        builder: (_) => const ProFeaturesScreen(),
                      ),
                    );
                  },
                  child: Text(t.proWelcome.setUp),
                ),
                secondary: TextButton(
                  key: const ValueKey('proWelcomeLater'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t.proWelcome.later),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
