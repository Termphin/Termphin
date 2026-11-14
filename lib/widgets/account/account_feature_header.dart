import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';

/// The head of a card on the account screen: its title, and a pill after
/// it - "Pro" in gold on a feature the account does not have yet.
class AccountFeatureHeader extends StatelessWidget {
  const AccountFeatureHeader({super.key, required this.title, this.badge});

  final String title;

  /// Sits after the title.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (badge != null) ...[const SizedBox(width: AppTheme.space8), badge!],
      ],
    );
  }
}
