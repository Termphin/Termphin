import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/account_provider.dart';
import '../../providers/sync_provider.dart';
import '../../screens/settings/account_screen.dart';
import '../ui/app_divider.dart';
import '../ui/settings_tile.dart';

/// A note under a setting that needs sync to work across devices, saying so
/// and opening the account where sync is turned on. It shows only while
/// signed in and while sync is not running on this device.
class SyncNeededTile extends ConsumerWidget {
  const SyncNeededTile({super.key, required this.message, this.divided = true});

  /// What the row needs sync for.
  final String message;

  /// Whether a divider comes before the note, for a card with rows above it.
  final bool divided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(accountProvider) == null) return const SizedBox.shrink();
    final t = Translations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: ref.watch(syncCoordinatorProvider).running,
      builder: (context, running, _) => running
          ? const SizedBox.shrink()
          : Column(
              children: [
                if (divided) const AppDivider(),
                SettingsTile(
                  icon: PhosphorIconsRegular.cloudSlash,
                  title: t.account.sync.needsSyncTitle,
                  subtitle: message,
                  destination: () => const AccountScreen(),
                ),
              ],
            ),
    );
  }
}
