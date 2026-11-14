import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/pro_source.dart';
import '../account/account_service.dart';
import '../analytics/analytics_service.dart';
import '../settings/setting.dart';
import 'pro_service.dart';

/// Whether Pro tips are shown at all. Off, no hint is offered or shown.
final Setting<bool> proTipsSetting = Setting.boolean(
  'pro_tips_enabled',
  fallback: true,
);

/// A moment when Pro would have helped, worth one quiet mention.
enum ProHint {
  /// A program's notification went out while Termphin was open in the
  /// background; with Pro it would also have reached a closed app.
  longCommand(ProSource.longCommandHint);

  const ProHint(this.source);

  final ProSource source;
}

/// Mentions Pro at the moments it would have helped, as one card on the
/// machine list at a time.
///
/// A hint is that card until the user closes it or opens Pro; it counts as
/// shown then, once ever, not when it appears. At most one card appears per
/// [minGap], never at launch, never to someone who has Pro or a build
/// without accounts, and never over a screen the user is not looking at: a
/// hint that comes up while the app is in the background waits for it to
/// come back. [current] is the card on screen, null when none is up.
class ProHints {
  ProHints._() {
    ProService.instance.settled.addListener(flush);
    ProService.instance.active.addListener(_onActiveChanged);
    proTipsSetting.addListener(_onTipsChanged);
  }

  static final instance = ProHints._();

  static const _prefsPrefix = 'pro_hint_shown_';
  static const _lastShownKey = 'pro_hint_last_shown_at';

  /// The least time between two cards, so a second hint waits until the
  /// first has been out of the way for a day.
  static const minGap = Duration(days: 1);

  /// The hint on screen now, null when no card is up.
  final current = ValueNotifier<ProHint?>(null);

  final _pending = <ProHint>{};
  DateTime? _lastShownAt;

  /// Forgets which hints were shown and when the last card came, so each can
  /// come again at its moment. For the debug panel.
  Future<void> forgetShown() async {
    _lastShownAt = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_lastShownKey);
    for (final hint in ProHint.values) {
      await preferences.remove('$_prefsPrefix${hint.name}');
    }
  }

  /// Notes that [hint]'s moment came. Shown as the card now if the app is in
  /// front and the gap allows, else on the next [flush].
  Future<void> offer(ProHint hint) async {
    if (!proTipsSetting.value) return;
    if (!AccountService.instance.available) return;
    if (ProService.instance.active.value) return;
    final preferences = await SharedPreferences.getInstance();
    _lastShownAt ??= _readLastShown(preferences);
    if (preferences.getBool('$_prefsPrefix${hint.name}') ?? false) return;
    _pending.add(hint);
    flush();
  }

  /// Puts the oldest waiting hint on screen as the card, if no card is up,
  /// the app is in front to show it, the account's Pro state is known and
  /// [minGap] has passed since the last card. Nothing waits for a hint once
  /// the account has Pro.
  void flush() {
    if (current.value != null || _pending.isEmpty) return;
    if (!proTipsSetting.value) return;
    if (ProService.instance.active.value) {
      _pending.clear();
      return;
    }
    if (!ProService.instance.settled.value) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    final now = clock.now();
    final lastShownAt = _lastShownAt;
    if (lastShownAt != null && now.isBefore(lastShownAt.add(minGap))) return;
    _lastShownAt = now;
    unawaited(
      SharedPreferences.getInstance().then(
        (preferences) =>
            preferences.setInt(_lastShownKey, now.millisecondsSinceEpoch),
      ),
    );
    final hint = _pending.first;
    current.value = hint;
    unawaited(
      AnalyticsService.instance.capture(
        AnalyticsEvent.proPromptShown,
        properties: {AnalyticsProperty.source: hint.source.id},
      ),
    );
  }

  /// Closes the card: its hint counts as shown, once ever. The next waiting
  /// hint may follow on a later [flush], once [minGap] has passed.
  void dismiss() {
    final hint = current.value;
    if (hint == null) return;
    _pending.remove(hint);
    current.value = null;
    unawaited(
      SharedPreferences.getInstance().then(
        (preferences) => preferences.setBool('$_prefsPrefix${hint.name}', true),
      ),
    );
    flush();
  }

  /// Puts [hint] on screen as the card at once, ignoring once-ever, the gap
  /// and Pro. For the debug panel.
  void showNow(ProHint hint) => current.value = hint;

  void _onActiveChanged() {
    if (!ProService.instance.active.value) return;
    _pending.clear();
    current.value = null;
  }

  void _onTipsChanged() {
    if (proTipsSetting.value) return;
    _pending.clear();
    current.value = null;
  }

  DateTime? _readLastShown(SharedPreferences preferences) {
    final milliseconds = preferences.getInt(_lastShownKey);
    if (milliseconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  /// Forgets what is waiting and on screen, so one test's hints do not show
  /// in the next.
  @visibleForTesting
  void reset() {
    _pending.clear();
    current.value = null;
    _lastShownAt = null;
  }
}
