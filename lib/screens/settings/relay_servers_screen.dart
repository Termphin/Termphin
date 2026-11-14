import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/anonymize_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/push/push_service.dart';
import '../../theme/theme.dart';
import '../../utils/relative_time.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/settings_tile.dart';

/// The servers that can reach this account while no phone is connected:
/// one row per relay key, with when it last sent something, and a way to
/// take a key away.
///
/// Keys are made on their own when a machine is connected with push on, so
/// there is nothing to add here - only to see and to revoke.
class RelayServersScreen extends ConsumerWidget {
  const RelayServersScreen({super.key});

  Future<void> _revoke(
    BuildContext context,
    RelayServer server,
    String name,
  ) async {
    final r = Translations.of(context).relayServers;
    final confirmed = await showConfirmDialog(
      context,
      title: r.revokeTitle(name: name),
      message: r.revokeMessage,
      confirmLabel: r.revoke,
      destructive: true,
    );
    if (confirmed) await PushService.instance.revoke(server);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = Translations.of(context).relayServers;
    final anonymize = ref.watch(anonymizeProvider);
    return LargeTitleScaffold(
      title: r.title,
      bodyBuilder: (context, scrollController, gutter) =>
          StreamBuilder<List<RelayServer>>(
            stream: PushService.instance.servers(),
            builder: (context, snapshot) {
              final servers = snapshot.data;
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space16,
                  0,
                  AppTheme.space16,
                  AppTheme.space32,
                ).add(gutter),
                children: [
                  LargeTitleHeader(title: r.title, subtitle: r.intro),
                  const SizedBox(height: AppTheme.space16),
                  if (servers == null)
                    const Center(child: CircularProgressIndicator())
                  else if (servers.isEmpty)
                    EmptyStatePanel(
                      icon: PhosphorIconsRegular.bellSimpleSlash,
                      title: r.empty,
                      subtitle: r.emptyHint,
                    )
                  else
                    AppCard.fields(
                      children: [
                        for (final (index, server) in servers.indexed) ...[
                          if (index > 0) const AppDivider(),
                          _row(context, server, anonymize),
                        ],
                      ],
                    ),
                ],
              );
            },
          ),
    );
  }

  Widget _row(BuildContext context, RelayServer server, bool anonymize) {
    final r = Translations.of(context).relayServers;
    final profileId = server.profileId;
    final name = anonymize && profileId != null
        ? IdentityAnonymizer.name(profileId)
        : server.label;
    final lastSent = server.lastSentAt;
    final createdAt = server.createdAt;
    return SettingsTile(
      icon: PhosphorIconsRegular.hardDrives,
      title: name,
      subtitle: lastSent != null
          ? r.lastSent(time: relativeTime(context, lastSent))
          : createdAt != null
          ? r.setUp(time: relativeTime(context, createdAt))
          : null,
      trailing: SettingsTileTrailing.none,
      trailingWidget: TextButton(
        onPressed: () => unawaited(_revoke(context, server, name)),
        style: TextButton.styleFrom(foregroundColor: context.colors.error),
        child: Text(r.revoke),
      ),
    );
  }
}
