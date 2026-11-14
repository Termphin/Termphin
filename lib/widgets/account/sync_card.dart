import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/pro_source.dart';
import '../../providers/groups_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/snippets_provider.dart';
import '../../providers/ssh_keys_provider.dart';
import '../../providers/sync_provider.dart';
import '../../screens/pro/pro_paywall_screen.dart';
import '../../services/pro/pro_service.dart';
import '../../services/sync/sync_coordinator.dart';
import '../../services/sync/sync_engine.dart';
import '../../services/sync/sync_service.dart';
import '../../theme/theme.dart';
import '../ui/app_badge.dart';
import '../ui/app_card.dart';
import '../ui/app_dropdown.dart';
import '../ui/app_notifications.dart';
import '../ui/confirm_dialog.dart';
import '../ui/text_input_dialog.dart';
import 'account_feature_header.dart';

/// Sync, on the account screen: turning it on with a passphrase, bringing
/// another device in with it, and leaving.
///
/// Once on, there is nothing to press: [SyncCoordinator] syncs on its own
/// and the card only reports it - when it last synced, that it is syncing,
/// or that the last attempt failed and will be retried. "Sync now" stays as
/// a quiet way to not wait. Without Pro the card still offers to turn sync
/// on, and the button opens the paywall instead.
class SyncCard extends ConsumerStatefulWidget {
  const SyncCard({super.key, this.service, this.coordinator, this.confirmPro});

  /// Stands in for [SyncService.instance] in tests.
  final SyncService? service;

  /// Stands in for [ProService.confirmOnServer] in tests.
  final Future<bool> Function()? confirmPro;

  /// Stands in for the app's [syncCoordinatorProvider] in tests.
  final SyncCoordinator? coordinator;

  @override
  ConsumerState<SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends ConsumerState<SyncCard> {
  SyncService get _sync => widget.service ?? SyncService.instance;

  /// Read once, in [initState]: [dispose] needs it to stop listening, and a
  /// widget being torn down may no longer read providers.
  late final SyncCoordinator _auto;

  SyncState? _state;
  bool _busy = false;

  /// The cloud refused the account for want of Pro. A state of the card,
  /// shown by the "Pro" pill and a button that leads to the paywall, not an
  /// error popping up every time the screen opens.
  bool _needsPro = false;

  /// The store says the account has Pro and the cloud does not know yet -
  /// the minutes after buying it. Waited out rather than sent to the
  /// paywall, which would offer Pro to someone who has just paid for it.
  bool _confirming = false;

  /// Waiting did not help: the server still has not heard. Offers to ask
  /// again rather than leaving a button that does nothing.
  bool _lagging = false;

  @override
  void initState() {
    super.initState();
    _auto = widget.coordinator ?? ref.read(syncCoordinatorProvider);
    ProService.instance.confirmed.addListener(_proChanged);
    _auto.ended.addListener(_endedElsewhere);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    ProService.instance.confirmed.removeListener(_proChanged);
    _auto.ended.removeListener(_endedElsewhere);
    super.dispose();
  }

  /// The server came to know about Pro - a purchase confirmed elsewhere,
  /// or the webhook arriving - so a refusal can be asked again.
  void _proChanged() {
    if (ProService.instance.confirmed.value && _needsPro) {
      unawaited(_refresh(confirm: false));
    }
  }

  /// Another device turned sync off or started it over: this one has just
  /// forgotten its key, so the card goes back to asking.
  void _endedElsewhere() {
    if (_auto.ended.value != null) unawaited(_refresh(confirm: false));
  }

  Future<void> _refresh({bool confirm = true}) async {
    SyncState state;
    var needsPro = false;
    try {
      state = await _sync.state();
    } on SyncException catch (error) {
      needsPro = error.failure == SyncFailure.notPro;
      if (mounted && !needsPro) _explain(error.failure);
      state = SyncState.notSetUp;
    } catch (_) {
      state = SyncState.notSetUp;
    }
    if (!mounted) return;
    if (needsPro && confirm && ProService.instance.active.value) {
      setState(() {
        _state = state;
        _needsPro = true;
        _confirming = true;
        _lagging = false;
      });
      final confirmed =
          await (widget.confirmPro ?? ProService.instance.confirmOnServer)();
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _lagging = !confirmed;
      });
      if (confirmed) await _refresh(confirm: false);
      return;
    }
    setState(() {
      _state = state;
      _needsPro = needsPro;
      if (!needsPro) _lagging = false;
    });
  }

  void _explain(SyncFailure failure) {
    final f = Translations.of(context).account.sync.failure;
    AppNotifications.error(context, switch (failure) {
      SyncFailure.wrongPassphrase => f.wrongPassphrase,
      SyncFailure.notPro => f.notPro,
      SyncFailure.network => f.network,
      SyncFailure.alreadySetUp => f.alreadySetUp,
      SyncFailure.turnedOff => f.turnedOff,
      SyncFailure.passphraseChanged => f.passphraseChanged,
      SyncFailure.unknown => f.unknown,
    });
  }

  /// Sets up or unlocks with [action], reloads what it brought in, says how
  /// it went, and hands over to automatic sync.
  Future<void> _begin(Future<SyncReport> Function() action) async {
    if (_busy) return;
    final t = Translations.of(context);
    setState(() => _busy = true);
    try {
      final report = await action();
      await _reloadData();
      if (mounted) {
        AppNotifications.success(
          context,
          t.account.sync.done(pulled: report.pulled, pushed: report.pushed),
        );
      }
      unawaited(_auto.start());
    } on SyncException catch (error) {
      if (error.failure == SyncFailure.notPro) {
        if (mounted) setState(() => _needsPro = true);
      } else if (mounted) {
        _explain(error.failure);
      }
    } catch (_) {
      if (mounted) _explain(SyncFailure.unknown);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _reloadData() async {
    await ref.read(profilesProvider.notifier).loadProfiles();
    await ref.read(profileGroupsProvider.notifier).loadGroups();
    await ref.read(snippetsProvider.notifier).loadSnippets();
    ref.read(sshKeysRevisionProvider.notifier).bump();
  }

  Future<void> _turnOn() async {
    if (_needsPro) {
      if (ProService.instance.active.value) {
        await _refresh();
      } else {
        await ProPaywallScreen.show(context, source: ProSource.syncCard);
      }
      return;
    }
    final s = Translations.of(context).account.sync;
    final first = await showTextInputDialog(
      context,
      title: s.choose,
      hintText: s.chooseHint,
      confirmLabel: s.turnOn,
      obscure: true,
      validator: (value) => (value ?? '').length < 8 ? s.tooShort : null,
    );
    if (first == null || !mounted) return;
    final second = await showTextInputDialog(
      context,
      title: s.repeat,
      confirmLabel: s.turnOn,
      obscure: true,
      validator: (value) => value != first ? s.mismatch : null,
    );
    if (second == null || !mounted) return;
    await _begin(() => _sync.setUp(first));
  }

  Future<void> _unlock() async {
    if (_needsPro) {
      if (ProService.instance.active.value) {
        await _refresh();
      } else {
        await ProPaywallScreen.show(context, source: ProSource.syncCard);
      }
      return;
    }
    final s = Translations.of(context).account.sync;
    final passphrase = await showTextInputDialog(
      context,
      title: s.passphrase,
      confirmLabel: s.unlock,
      obscure: true,
    );
    if (passphrase == null || !mounted) return;
    await _begin(() => _sync.unlock(passphrase));
  }

  Future<void> _syncNow() async {
    final report = await _auto.syncNow();
    if (!mounted) return;
    final s = Translations.of(context).account.sync;
    if (report == null) {
      _explain(SyncFailure.unknown);
    } else {
      AppNotifications.success(
        context,
        s.done(pulled: report.pulled, pushed: report.pushed),
      );
    }
  }

  Future<void> _turnOff() async {
    final s = Translations.of(context).account.sync;
    final confirmed = await showConfirmDialog(
      context,
      title: s.turnOffTitle,
      message: s.turnOffMessage,
      confirmLabel: s.turnOff,
    );
    if (!confirmed) return;
    _auto.stop();
    await _sync.forgetOnThisDevice();
    await _refresh();
  }

  /// Turns sync off on every device and deletes the synced copy - also the
  /// way out of a forgotten passphrase. Needs no Pro.
  Future<void> _deleteEverywhere() async {
    final s = Translations.of(context).account.sync;
    final confirmed = await showConfirmDialog(
      context,
      title: s.deleteAllTitle,
      message: s.deleteAllMessage,
      confirmLabel: s.deleteAllConfirm,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      _auto.stop();
      await _sync.deleteEverywhere();
      if (mounted) AppNotifications.success(context, s.deleted);
    } on SyncException catch (error) {
      if (mounted) _explain(error.failure);
    } catch (_) {
      if (mounted) _explain(SyncFailure.unknown);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh(confirm: false);
    }
  }

  void _renew() =>
      unawaited(ProPaywallScreen.show(context, source: ProSource.syncCard));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ProService.instance.active,
      _auto.activity,
      _auto.ended,
    ]),
    builder: (context, _) => _card(context),
  );

  Widget _card(BuildContext context) {
    final t = Translations.of(context);
    final s = t.account.sync;
    final text = Theme.of(context).textTheme;
    final state = _state;
    final pro = ProService.instance.active.value;
    final paused =
        state == SyncState.ready && _auto.activity.value == SyncActivity.paused;
    final ended = _auto.ended.value;
    final String? note = switch ((state, ended)) {
      (SyncState.notSetUp, SyncFailure.turnedOff) => s.turnedOffElsewhere,
      (SyncState.locked, SyncFailure.passphraseChanged) => s.rekeyedElsewhere,
      _ => null,
    };
    return AppCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AccountFeatureHeader(
                  title: s.title,
                  badge: paused
                      ? AppBadge(s.pausedBadge, tone: BadgeTone.warning)
                      : _needsPro && !pro
                      ? AppBadge(t.account.pro.badge, tone: BadgeTone.pro)
                      : state == SyncState.ready
                      ? AppBadge(s.onBadge, tone: BadgeTone.success)
                      : null,
                ),
              ),
              if (state == SyncState.ready) _menu(context),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          if (state == null)
            const LinearProgressIndicator()
          else if (_confirming) ...[
            Text(s.confirming, style: text.bodyMedium),
            const SizedBox(height: AppTheme.space10),
            const LinearProgressIndicator(),
          ] else if (_lagging)
            Text(s.lagging, style: text.bodyMedium)
          else if (paused)
            Text(s.paused, style: text.bodyMedium)
          else if (state == SyncState.ready)
            _AutoStatus(coordinator: _auto)
          else
            Text(
              note ??
                  (state == SyncState.locked && !_needsPro ? s.locked : s.off),
              style: text.bodyMedium,
            ),
          const SizedBox(height: AppTheme.space14),
          if (paused)
            FilledButton(onPressed: _busy ? null : _renew, child: Text(s.renew))
          else if (state == SyncState.ready)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _busy ? null : _syncNow,
                child: Text(s.syncNow),
              ),
            )
          else if (_lagging)
            OutlinedButton(onPressed: _refresh, child: Text(s.retry))
          else if (!_confirming) ...[
            FilledButton(
              onPressed: _busy || state == null
                  ? null
                  : state == SyncState.locked
                  ? _unlock
                  : _turnOn,
              child: Text(
                _busy
                    ? s.syncing
                    : state == SyncState.locked && !_needsPro
                    ? s.unlock
                    : s.turnOn,
              ),
            ),
            if (state == SyncState.locked)
              TextButton(
                onPressed: _busy ? null : _deleteEverywhere,
                child: Text(s.forgot),
              ),
          ],
        ],
      ),
    );
  }

  /// Leaving sync, on this device or everywhere.
  Widget _menu(BuildContext context) {
    final s = Translations.of(context).account.sync;
    return AppActionDropdown<_SyncAction>(
      iconSize: AppTheme.icon18,
      items: [
        DropdownItem(
          value: _SyncAction.stopHere,
          intrinsicHeight: true,
          child: AppDropdownItem(
            icon: PhosphorIconsRegular.deviceMobileSlash,
            label: s.turnOff,
          ),
        ),
        DropdownItem(
          value: _SyncAction.deleteAll,
          intrinsicHeight: true,
          child: AppDropdownItem(
            icon: PhosphorIconsRegular.trash,
            label: s.deleteAll,
            color: context.colors.error,
          ),
        ),
      ],
      onSelected: (action) => switch (action) {
        _SyncAction.stopHere => unawaited(_turnOff()),
        _SyncAction.deleteAll => unawaited(_deleteEverywhere()),
      },
    );
  }
}

enum _SyncAction { stopHere, deleteAll }

/// What automatic sync is doing, kept current as it works.
class _AutoStatus extends StatelessWidget {
  const _AutoStatus({required this.coordinator});

  final SyncCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final s = Translations.of(context).account.sync;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([
        coordinator.activity,
        coordinator.lastSynced,
      ]),
      builder: (context, _) {
        final last = coordinator.lastSynced.value;
        final line = switch (coordinator.activity.value) {
          SyncActivity.syncing => s.syncing,
          SyncActivity.failed => s.failedRetry,
          SyncActivity.paused => s.paused,
          SyncActivity.idle =>
            last == null
                ? s.auto
                : s.autoLast(
                    time: MaterialLocalizations.of(
                      context,
                    ).formatTimeOfDay(TimeOfDay.fromDateTime(last)),
                  ),
        };
        return Text(
          line,
          style: text.bodyMedium?.copyWith(
            color: coordinator.activity.value == SyncActivity.failed
                ? context.colors.warning
                : null,
          ),
        );
      },
    );
  }
}
