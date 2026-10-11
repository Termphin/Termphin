import 'package:flutter/material.dart';

import '../../services/app/app_commands.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';

/// The keys that do what a menu row does, printed quietly at its far end -
/// where a desktop user learns them without opening a list of shortcuts.
///
/// [of] and [ofCommand] return null on a phone, which has no keyboard to
/// press them on, so a row can hand the result straight to a `trailing`.
class ShortcutHint extends StatelessWidget {
  const ShortcutHint(this.keys, {super.key});

  final String keys;

  static Widget? of(SingleActivator activator) => isDesktopPlatform
      ? ShortcutHint(AppCommands.describeActivator(activator))
      : null;

  static Widget? ofCommand(AppCommand command) {
    if (!isDesktopPlatform) return null;
    final keys = AppCommands.shortcutLabel(command);
    return keys == null ? null : ShortcutHint(keys);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 12),
    child: Text(
      keys,
      style: context.colors.uiSmall.copyWith(
        fontSize: 12,
        color: context.colors.textTertiary,
      ),
    ),
  );
}
