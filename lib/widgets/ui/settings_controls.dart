import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';
import 'app_dropdown.dart';

/// The controls the appearance screens are built from - the terminal's and
/// the text editor's - so the two read as one set of settings.
///
/// A labelled, full-width dropdown - the shape the style settings are built
/// from, rather than the same forty lines of `DropdownButton2` three times.
class SettingsDropdownField<T> extends StatelessWidget {
  const SettingsDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.labels,
    required this.onChanged,
    this.itemFontFamily,
  });

  final String label;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  /// The font each option is drawn in, for the font picker itself; null
  /// keeps the interface face.
  final String? Function(T value)? itemFontFamily;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppTheme.space8),
        _SettingsDropdown<T>(
          value: value,
          labels: labels,
          onChanged: onChanged,
          itemFontFamily: itemFontFamily,
          compact: false,
        ),
      ],
    );
  }
}

/// The same picker as [SettingsDropdownField], laid out as a row for short lists.
class SettingsDropdownRow<T> extends StatelessWidget {
  const SettingsDropdownRow({
    super.key,
    required this.label,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        _SettingsDropdown<T>(
          value: value,
          labels: labels,
          onChanged: onChanged,
          compact: true,
        ),
      ],
    );
  }
}

/// The button both settings dropdowns share; [compact] is the row variant,
/// sized to its content instead of the full width.
class _SettingsDropdown<T> extends StatelessWidget {
  const _SettingsDropdown({
    required this.value,
    required this.labels,
    required this.onChanged,
    required this.compact,
    this.itemFontFamily,
  });

  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;
  final bool compact;
  final String? Function(T value)? itemFontFamily;

  @override
  Widget build(BuildContext context) {
    final caret = compact ? AppTheme.icon14 : AppTheme.icon16;
    final selectedStyle = TextStyle(
      color: context.colors.textSecondary,
      fontSize: AppTheme.font14,
      fontWeight: FontWeight.w500,
    );
    return DropdownButton2<T>(
      valueListenable: ValueNotifier(value),
      isExpanded: !compact,
      underline: const SizedBox.shrink(),
      selectedItemBuilder: (context) => labels.values
          .map(
            (v) => compact
                ? Text(v, style: selectedStyle)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Text(v, style: selectedStyle),
                  ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      buttonStyleData: ButtonStyleData(
        height: compact ? 40 : 48,
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.space12,
          vertical: compact ? AppTheme.space8 : AppTheme.space12,
        ),
        decoration: context.colors.fieldDecoration,
        elevation: 0,
      ),
      iconStyleData: IconStyleData(
        icon: Icon(
          PhosphorIconsFill.caretDown,
          size: caret,
          color: context.colors.textTertiary,
        ),
        iconSize: caret,
      ),
      dropdownStyleData: appDropdownStyle(
        context,
        maxHeight: compact ? null : 300,
      ),
      menuItemStyleData: appDropdownItemStyle(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space10),
      ),
      items: labels.entries
          .map(
            (e) => DropdownItem<T>(
              value: e.key,
              intrinsicHeight: true,
              child: AppDropdownItem(
                label: e.value,
                fontFamily: itemFontFamily?.call(e.key),
                selected: e.key == value,
              ),
            ),
          )
          .toList(),
    );
  }
}
