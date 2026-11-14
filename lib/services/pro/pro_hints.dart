import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/pro_source.dart';
import '../account/account_service.dart';
import '../analytics/analytics_service.dart';
import 'pro_service.dart';

/// A moment when Pro would have helped, worth one quiet mention.
enum ProHint {
  /// A program's notification went out while Termphin was open in the
  /// background; with Pro it would also have reached a closed app.
  longCommand(ProSource.longCommandHint),

  /// A session was picked up again after its connection dropped; with Pro
  /// a program in it could have called for the user meanwhile.
  droppedSession(ProSource.droppedSessionHint),

  /// Enough machines that having them on another device starts to matter.
  machines(ProSource.machinesHint);

  const ProHint(this.source);

  final ProSource source;
}

/// Mentions Pro at the moments it would have helped, each one once ever.
///
/// Never at launch, never twice, never to someone who has Pro or a build
/// without accounts, and never over a screen the user is not looking at: a
/// hint that comes up while the app is in the background waits for it to
/// come back. [present] is what shows it - the app gate, which has a
/// navigator - and stays null in tests and before the app is up.
class ProHints {
  ProHints._() {
    ProService.instance.settled.addListener(flush);
  }

  static final instance = ProHints._();

  static const _prefsPrefix = 'pro_hint_shown_';

  /// Shows [hint] and resolves true once it is on screen; false leaves it
  /// waiting for the next [flush]. Set once the app has a navigator to show
  /// it on.
  Future<bool> Function(ProHint hint)? present;

  final _pending = <ProHint>{};
  bool _presenting = false;

  /// How many machines make [ProHint.machines] worth saying.
  static const machinesThreshold = 5;

  /// Notes that [hint]'s moment came. Shown now if the app is in front,
  /// else on the next [flush].
  Future<void> offer(ProHint hint) async {
    if (!AccountService.instance.available) return;
    if (ProService.instance.active.value) return;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool('$_prefsPrefix${hint.name}') ?? false) return;
    _pending.add(hint);
    flush();
  }

  /// Shows the oldest waiting hint, if the app is in front to show it and
  /// the account's Pro state is known. Nothing waits for a hint once the
  /// account has Pro.
  void flush() {
    final present = this.present;
    if (present == null || _pending.isEmpty || _presenting) return;
    if (ProService.instance.active.value) {
      _pending.clear();
      return;
    }
    if (!ProService.instance.settled.value) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    _presenting = true;
    unawaited(_show(present, _pending.first));
  }

  /// Presents [hint]: marked shown and logged only once it is on screen, so
  /// a hint that found no place to show stays pending.
  Future<void> _show(
    Future<bool> Function(ProHint hint) present,
    ProHint hint,
  ) async {
    var shown = false;
    try {
      shown = await present(hint);
    } finally {
      _presenting = false;
    }
    if (!shown) return;
    _pending.remove(hint);
    unawaited(
      SharedPreferences.getInstance().then(
        (preferences) => preferences.setBool('$_prefsPrefix${hint.name}', true),
      ),
    );
    unawaited(
      AnalyticsService.instance.capture(
        AnalyticsEvent.proPromptShown,
        properties: {AnalyticsProperty.source: hint.source.id},
      ),
    );
  }

  /// Forgets what is waiting, so one test's hints do not show in the next.
  @visibleForTesting
  void reset() {
    _pending.clear();
    _presenting = false;
  }
}
