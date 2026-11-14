// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:material_ui/material_ui.dart';

/// The ancestor a widget from a package still built on the framework's own
/// Material library looks for, and does not find under `material_ui`'s.
///
/// The app draws with `material_ui`, whose `Material` is a type of its own,
/// however alike the two read. `dropdown_button2` asks for the framework's
/// one by type and throws without it, and reads the framework's theme and
/// localizations, which `MaterialUiCompatibilityBridge` hands across. The
/// bridge is taken along here rather than relied on from the app's root, so
/// the widget works wherever it is built. Transparent, so it paints nothing
/// of its own. Goes once the packages it wraps have moved to `material_ui`.
class LegacyMaterial extends StatelessWidget {
  const LegacyMaterial({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      legacy.Material(type: legacy.MaterialType.transparency, child: child);
}
