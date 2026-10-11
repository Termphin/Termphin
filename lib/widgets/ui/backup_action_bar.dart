import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'modal_actions.dart';

/// The one action of a backup screen, pinned under the scroll.
///
/// Export and import are both a long list of choices ending in a single
/// commit, and a button that scrolls away with the list is one the user has
/// to go looking for after every change of mind.
class BackupActionBar extends StatelessWidget {
  const BackupActionBar({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  /// An outlined button above the primary one - the import screen's "choose
  /// another file".
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: context.colors.backgroundPrimary,
        border: Border(top: BorderSide(color: context.colors.surfaceDivider)),
      ),
      child: ModalActions(
        secondaryFirst: true,
        secondary: switch (secondaryLabel) {
          final secondary? => OutlinedButton(
            onPressed: onSecondaryPressed,
            child: Text(secondary),
          ),
          null => null,
        },
        primary: ElevatedButton.icon(
          onPressed: onPressed,
          icon: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.onPrimary,
                  ),
                )
              : Icon(icon, size: 20),
          label: Text(label),
        ),
      ),
    );
  }
}
