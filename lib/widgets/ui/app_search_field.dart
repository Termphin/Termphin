import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';

/// The search box at the top of a list screen.
///
/// The machines list and the snippets list had grown their own copies of the
/// same forty lines - same magnifying glass, same vertical padding, same
/// clear button - so a change to one silently left the other behind.
///
/// [trailing] is for whatever a screen wants next to the clear button (a sort
/// menu, say); the clear button appears on its own as soon as there is text.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.clearTooltip,
    required this.onChanged,
    this.focusNode,
    this.trailing,
  });

  final TextEditingController controller;
  final String hint;
  final String clearTooltip;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final clearButton = controller.text.isEmpty
        ? null
        : IconButton(
            tooltip: clearTooltip,
            onPressed: () {
              controller.clear();
              onChanged('');
            },
            icon: Icon(
              PhosphorIconsRegular.x,
              size: 16,
              color: context.colors.textTertiary,
            ),
          );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: false,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      onChanged: onChanged,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        prefixIcon: Icon(
          PhosphorIconsFill.magnifyingGlass,
          size: 18,
          color: context.colors.textTertiary,
        ),
        suffixIcon: trailing == null
            ? clearButton
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [?clearButton, trailing!],
              ),
      ),
    );
  }
}
