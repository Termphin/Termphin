import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../providers/groups_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/snippets_provider.dart';
import '../../providers/ssh_keys_provider.dart';
import '../../services/sync/sync_engine.dart';
import '../../services/sync/sync_service.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/app_notifications.dart';
import '../ui/confirm_dialog.dart';
import '../ui/text_input_dialog.dart';

/// Sync, on the account screen: turning it on with a passphrase, bringing
/// another device in with it, syncing, and leaving.
class SyncCard extends ConsumerStatefulWidget {
  const SyncCard({super.key, this.service});

  /// Stands in for [SyncService.instance] in tests.
  final SyncService? service;

  @override
  ConsumerState<SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends ConsumerState<SyncCard> {
  SyncService get _sync => widget.service ?? SyncService.instance;

  SyncState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    SyncState state;
    try {
      state = await _sync.state();
    } on SyncException catch (error) {
      if (mounted) _explain(error.failure);
      state = SyncState.notSetUp;
    } catch (_) {
      state = SyncState.notSetUp;
    }
    if (mounted) setState(() => _state = state);
  }

  void _explain(SyncFailure failure) {
    final f = Translations.of(context).account.sync.failure;
    AppNotifications.error(context, switch (failure) {
      SyncFailure.wrongPassphrase => f.wrongPassphrase,
      SyncFailure.notPro => f.notPro,
      SyncFailure.network => f.network,
      SyncFailure.alreadySetUp => f.alreadySetUp,
      SyncFailure.unknown => f.unknown,
    });
  }

  /// Runs [action], reloads what it may have changed on this device, and
  /// says how it went.
  Future<void> _run(Future<SyncReport> Function() action) async {
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
    } on SyncException catch (error) {
      if (mounted) _explain(error.failure);
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
    await _run(() => _sync.setUp(first));
  }

  Future<void> _unlock() async {
    final s = Translations.of(context).account.sync;
    final passphrase = await showTextInputDialog(
      context,
      title: s.passphrase,
      confirmLabel: s.unlock,
      obscure: true,
    );
    if (passphrase == null || !mounted) return;
    await _run(() => _sync.unlock(passphrase));
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
    await _sync.forgetOnThisDevice();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final s = t.account.sync;
    final text = Theme.of(context).textTheme;
    final state = _state;
    final last = _sync.lastSynced.value;
    final (String body, String action, VoidCallback onAction) = switch (state) {
      SyncState.ready => (
        last == null
            ? s.neverSynced
            : s.lastSynced(
                time: MaterialLocalizations.of(
                  context,
                ).formatTimeOfDay(TimeOfDay.fromDateTime(last)),
              ),
        s.syncNow,
        () => _run(_sync.syncNow),
      ),
      SyncState.locked => (s.locked, s.unlock, _unlock),
      _ => (s.off, s.turnOn, _turnOn),
    };
    return AppCard(
      padding: const EdgeInsets.all(AppTheme.space14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.title, style: text.titleMedium),
          const SizedBox(height: AppTheme.space6),
          if (state == null)
            const LinearProgressIndicator()
          else
            Text(
              body,
              style: text.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          const SizedBox(height: AppTheme.space12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy || state == null ? null : onAction,
                  child: Text(_busy ? s.syncing : action),
                ),
              ),
            ],
          ),
          if (state == SyncState.ready)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : _turnOff,
                child: Text(s.turnOff),
              ),
            ),
        ],
      ),
    );
  }
}
