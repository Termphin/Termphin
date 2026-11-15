import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';

/// Rows a card shows only in some states - the PIN's own rows while there
/// is one - grown and shrunk into place rather than popped in.
class SettingsRowsReveal extends StatelessWidget {
  const SettingsRowsReveal({
    super.key,
    required this.visible,
    required this.children,
  });

  final bool visible;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppTheme.motionSlow,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: visible
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
