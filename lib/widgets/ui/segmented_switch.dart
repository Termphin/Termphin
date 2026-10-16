import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';

/// One half (or third) of a [SegmentedSwitch].
class SwitchSegment<T> {
  const SwitchSegment({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
    this.key,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? tooltip;

  /// Put on the segment's tap target, for tests and the screenshot harness.
  final Key? key;
}

/// The app's segmented control: a recessed track with a raised thumb that
/// slides to the picked segment.
///
/// One widget, so the tab menu's terminal/files switch and the session's quick
/// sheet are the same control rather than two that drift apart.
///
/// The thumb's radius is concentric with the track's, so the gap around it
/// is even all the way round its corners, and it slides between segments
/// rather than appearing on the other side, so a change reads as one
/// control moving. It is a recessed track with a raised thumb: lighter
/// than the track in a dark scheme, the page colour in a light one, where
/// a darker thumb would read as pressed in rather than picked.
class SegmentedSwitch<T> extends StatelessWidget {
  const SegmentedSwitch({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.thumbKey,
  });

  static const _height = 40.0;
  static const _inset = 3.0;

  final List<SwitchSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final Key? thumbKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppTheme.radiusMd - _inset);
    final dark = colors.brightness == Brightness.dark;
    final track = dark ? colors.backgroundPrimary : colors.surfaceOffset2;
    final thumb = dark ? colors.surfaceOffset2 : colors.backgroundPrimary;
    final index = segments.indexWhere((s) => s.value == selected);

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      padding: const EdgeInsets.all(_inset),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / segments.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: AppTheme.motionFast,
                curve: Curves.easeOutCubic,
                left: (index < 0 ? 0 : index) * segmentWidth,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: DecoratedBox(
                  key: thumbKey,
                  decoration: BoxDecoration(color: thumb, borderRadius: radius),
                ),
              ),
              Row(
                children: [
                  for (final segment in segments)
                    Expanded(child: _segment(context, segment, radius)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    SwitchSegment<T> segment,
    BorderRadius radius,
  ) {
    final target = Material(
      color: context.colors.backgroundPrimary.invisible,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: segment.key,
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(segment.value);
        },
        child: _SegmentLabel(
          icon: segment.icon,
          label: segment.label,
          selected: segment.value == selected,
        ),
      ),
    );
    final tooltip = segment.tooltip;
    return tooltip == null ? target : Tooltip(message: tooltip, child: target);
  }
}

/// The words carry the contrast; the accent is only on the picked side's icon.
class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData? icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? colors.textPrimary : colors.textSecondary;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: AppTheme.icon16,
              color: selected ? colors.primary : color,
            ),
            const SizedBox(width: AppTheme.space6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: AppTheme.font13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
