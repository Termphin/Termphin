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

/// How tall the strip under the active session is while another device
/// holds it ([ControlBar]), 0 without one, for anything floating over the
/// bottom of the screen - the assistant - to sit above it.
final ValueNotifier<double> controlBarHeight = ValueNotifier(0);

/// [child] - the control strip, or nothing - telling [controlBarHeight] how
/// tall it is while its session is the active one, after each frame, since
/// it is read by a widget elsewhere in the tree.
class ControlBarHeightReporter extends StatefulWidget {
  const ControlBarHeightReporter({
    super.key,
    required this.active,
    required this.child,
    this.target,
  });

  final bool active;
  final Widget? child;

  /// Where the height goes; [controlBarHeight] unless a test says otherwise.
  final ValueNotifier<double>? target;

  @override
  State<ControlBarHeightReporter> createState() =>
      _ControlBarHeightReporterState();
}

class _ControlBarHeightReporterState extends State<ControlBarHeightReporter> {
  ValueNotifier<double> get _target => widget.target ?? controlBarHeight;

  void _publish() {
    if (!mounted || !widget.active) return;
    final box = context.findRenderObject();
    final height = widget.child != null && box is RenderBox && box.hasSize
        ? box.size.height
        : 0.0;
    if (_target.value != height) _target.value = height;
  }

  @override
  void dispose() {
    if (widget.active) _target.value = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
    return widget.child ?? const SizedBox.shrink();
  }
}
