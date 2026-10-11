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
class SettingsDropdownField extends StatelessWidget {
  const SettingsDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.labels,
    required this.onChanged,
    this.itemsInOwnFont = false,
  });

  final String label;
  final String value;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;

  /// Renders each option in the font it names, for the font picker itself.
  final bool itemsInOwnFont;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        DropdownButton2<String>(
          valueListenable: ValueNotifier(value),
          isExpanded: true,
          underline: const SizedBox.shrink(),
          selectedItemBuilder: (context) => labels.values
              .map(
                (v) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    v,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          buttonStyleData: ButtonStyleData(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.fieldFill,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: context.colors.surfaceBorder),
            ),
            elevation: 0,
          ),
          iconStyleData: IconStyleData(
            icon: Icon(
              PhosphorIconsFill.caretDown,
              size: 16,
              color: context.colors.textTertiary,
            ),
            iconSize: 16,
          ),
          dropdownStyleData: appDropdownStyle(context, maxHeight: 300),
          menuItemStyleData: appDropdownItemStyle(
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          items: labels.entries
              .map(
                (e) => DropdownItem<String>(
                  value: e.key,
                  intrinsicHeight: true,
                  child: AppDropdownItem(
                    label: e.value,
                    fontFamily: itemsInOwnFont ? e.key : null,
                    selected: e.key == value,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

/// The same picker as [SettingsDropdownField], laid out as a row for short lists.
class SettingsDropdownRow extends StatelessWidget {
  const SettingsDropdownRow({
    super.key,
    required this.label,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        DropdownButton2<String>(
          valueListenable: ValueNotifier(value),
          underline: const SizedBox.shrink(),
          selectedItemBuilder: (context) => labels.values
              .map(
                (v) => Text(
                  v,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          buttonStyleData: ButtonStyleData(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.colors.fieldFill,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: context.colors.surfaceBorder),
            ),
            elevation: 0,
          ),
          iconStyleData: IconStyleData(
            icon: Icon(
              PhosphorIconsFill.caretDown,
              size: 14,
              color: context.colors.textTertiary,
            ),
            iconSize: 14,
          ),
          dropdownStyleData: appDropdownStyle(context),
          menuItemStyleData: appDropdownItemStyle(
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          items: labels.entries
              .map(
                (e) => DropdownItem<String>(
                  value: e.key,
                  intrinsicHeight: true,
                  child: AppDropdownItem(
                    label: e.value,
                    selected: e.key == value,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: context.colors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
