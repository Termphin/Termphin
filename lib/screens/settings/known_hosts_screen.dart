import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/known_host.dart';
import '../../providers/anonymize_provider.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/storage/known_hosts_store.dart';
import '../../theme/theme.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/large_title_scaffold.dart';

/// The host keys this device has pinned, and the only way to un-pin one.
///
/// Without it a host whose key legitimately rotated could only be re-trusted
/// through the scare dialog that fires mid-connect - a place where the right
/// answer is "stop and check", not "read the fine print". Forgetting the key
/// here puts the next connection back at first contact instead.
class KnownHostsScreen extends ConsumerStatefulWidget {
  const KnownHostsScreen({super.key, this.store});

  /// The pin store to read and un-pin through. Defaults to the app's own; a
  /// test passes its own so the un-pin it performs is not carried into the
  /// next one by the singleton's write queue.
  final KnownHostsStore? store;

  @override
  ConsumerState<KnownHostsScreen> createState() => _KnownHostsScreenState();
}

class _KnownHostsScreenState extends ConsumerState<KnownHostsScreen> {
  List<KnownHost>? _hosts;

  KnownHostsStore get _store => widget.store ?? KnownHostsStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.knownHosts));
    _load();
  }

  Future<void> _load() async {
    final hosts = await _store.entries();
    if (!mounted) return;
    setState(() => _hosts = hosts);
  }

  Future<void> _forget(KnownHost host) async {
    final t = Translations.of(context);
    final anonymize = ref.read(anonymizeProvider);
    final displayHost = anonymize
        ? IdentityAnonymizer.host(host.host)
        : host.host;
    final confirmed = await showConfirmDialog(
      context,
      title: t.settings.knownHostsForgetTitle,
      message: t.settings.knownHostsForgetBody(
        host: '$displayHost:${host.port}',
      ),
      confirmLabel: t.settings.knownHostsForget,
      destructive: true,
    );
    if (!confirmed) return;
    await _store.forgetSlot(host.slot);
    if (!mounted) return;
    AppNotifications.success(context, t.settings.knownHostsForgotten);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final hosts = _hosts;
    return Scaffold(
      appBar: AppBar(title: Text(t.settings.knownHosts)),
      body: SafeArea(
        top: false,
        child: hosts == null
            ? const SizedBox.shrink()
            : hosts.isEmpty
            ? EmptyStatePanel(
                icon: PhosphorIconsRegular.shieldCheck,
                title: t.settings.knownHostsEmpty,
                subtitle: t.settings.knownHostsEmptyBody,
              )
            : ContentGutter(
                builder: (context, gutter) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    32,
                  ).add(gutter),
                  itemCount: hosts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) =>
                      _HostCard(host: hosts[index], onForget: _forget),
                ),
              ),
      ),
    );
  }
}

class _HostCard extends ConsumerWidget {
  const _HostCard({required this.host, required this.onForget});

  final KnownHost host;
  final void Function(KnownHost host) onForget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final anonymize = ref.watch(anonymizeProvider);
    final displayHost = anonymize
        ? IdentityAnonymizer.host(host.host)
        : host.host;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$displayHost:${host.port}',
                    style: colors.itemTitle,
                  ),
                ),
                TextButton(
                  onPressed: () => onForget(host),
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  child: Text(t.settings.knownHostsForget),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceXs),
            SelectableText(host.fingerprint, style: colors.monoSmall),
            const SizedBox(height: AppTheme.spaceXs),
            Text(
              '${host.keyType} · '
              '${t.settings.knownHostsAddedAt(date: DateFormat.yMMMd().format(host.addedAt))}',
              style: colors.uiSmall.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
