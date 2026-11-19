import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import 'confirm_dialog.dart';

/// Asks before a form with unsaved changes is left by the back gesture, the
/// system back button or a close button that goes through
/// `Navigator.maybePop`. Saving pops with `Navigator.pop` and is never asked.
///
/// [dirty] is read on every rebuild of the form and on every change of
/// [changes] - its text fields, which change without the form rebuilding -
/// so a form with nothing changed still lets the back gesture through.
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.dirty,
    this.changes,
    required this.child,
  });

  final bool Function() dirty;
  final Listenable? changes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final changes = this.changes;
    if (changes == null) return _scope(context, child);
    return ListenableBuilder(
      listenable: changes,
      builder: (context, child) => _scope(context, child!),
      child: child,
    );
  }

  Widget _scope(BuildContext context, Widget child) => PopScope(
    canPop: !dirty(),
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final t = Translations.of(context);
      final leave = await showConfirmDialog(
        context,
        title: t.common.unsavedTitle,
        message: t.common.unsavedMessage,
        confirmLabel: t.common.discard,
        destructive: true,
      );
      if (leave && context.mounted) Navigator.of(context).pop();
    },
    child: child,
  );
}
