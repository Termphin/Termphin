import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/session_control.dart';
import '../../theme/theme.dart';
import 'attached_devices.dart';

/// Shown under a session another device holds: which device that is, and a
/// button to take the session from it.
///
/// A full-width strip fixed to the bottom of the session - right above the
/// tab bar when the tabs sit at the bottom, above the key toolbar
/// otherwise - with a hairline on top like the toolbar's, rather than a
/// card floating over the terminal it would hide part of.
///
/// Taking control is always a tap on this button and never a keystroke, so
/// two devices - or, later, two people - cannot pull the session back and
/// forth by typing at once.
class ControlBar extends StatelessWidget {
  const ControlBar({super.key, required this.control, required this.onTake});

  final SessionControl control;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).terminal.control;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final device = control.device;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        border: Border(
          top: BorderSide(
            color: colors.surfaceBorder,
            width: AppTheme.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space14,
          AppTheme.space6,
          AppTheme.space10,
          AppTheme.space6,
        ),
        child: Row(
          children: [
            Icon(
              device == null
                  ? PhosphorIconsRegular.devices
                  : AttachedDevices.iconFor(device.kind),
              size: AppTheme.icon20,
              color: colors.textSecondary,
            ),
            const SizedBox(width: AppTheme.space10),
            Expanded(
              child: Text(
                device == null
                    ? t.heldElsewhere
                    : t.heldBy(device: device.name),
                key: const ValueKey('controlHolder'),
                style: text.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppTheme.space8),
            TextButton(
              key: const ValueKey('takeControl'),
              onPressed: onTake,
              style: TextButton.styleFrom(
                foregroundColor: colors.primary,
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, AppTheme.space32),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space10,
                ),
                textStyle: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(t.take),
            ),
          ],
        ),
      ),
    );
  }
}
