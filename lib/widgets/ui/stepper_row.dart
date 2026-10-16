import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';

/// A labelled +/- pair that lands on an exact integer value. Settings that
/// used to be sliders use this instead - a stepper hits the value you want
/// on the first try.
class StepperRow extends StatelessWidget {
  const StepperRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          _StepperButton(
            icon: PhosphorIconsRegular.minus,
            onTap: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _StepperButton(
            icon: PhosphorIconsRegular.plus,
            onTap: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// The double-valued sibling of [StepperRow]. Sliders were what these used
/// to be; a stepper hits an exact value on the first try, which is what a
/// font size or a line height actually needs.
class ValueStepperRow extends StatelessWidget {
  const ValueStepperRow({
    super.key,
    required this.label,
    required this.value,
    required this.display,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String display;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  /// Steps land on multiples of [step] from [min], so a value nudged off the
  /// grid by an older build snaps back onto it instead of carrying the offset
  /// forever.
  double _stepped(int direction) {
    final steps = ((value - min) / step).round() + direction;
    final next = min + steps * step;
    return next.clamp(min, max);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          _StepperButton(
            icon: PhosphorIconsRegular.minus,
            onTap: value > min ? () => onChanged(_stepped(-1)) : null,
          ),
          SizedBox(
            width: 46,
            child: Text(
              display,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _StepperButton(
            icon: PhosphorIconsRegular.plus,
            onTap: value < max ? () => onChanged(_stepped(1)) : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: context.colors.surfaceCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: context.colors.surfaceBorder),
          ),
          child: Icon(
            icon,
            size: AppTheme.icon14,
            color: enabled
                ? context.colors.textSecondary
                : context.colors.textTertiary,
          ),
        ),
      ),
    );
  }
}
