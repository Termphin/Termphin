import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/agent_feature.dart';
import '../../theme/theme.dart';

/// What a session started with an older agent does without, one line per
/// feature, and the way to a session that has them all. Pops `true` when
/// the user asks for a new session.
class OlderSessionSheet extends StatelessWidget {
  const OlderSessionSheet({super.key, required this.missing});

  final List<AgentFeature> missing;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final a = t.agentFeatures;
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space24,
        AppTheme.space8,
        AppTheme.space24,
        AppTheme.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(a.title, style: text.titleLarge),
          const SizedBox(height: AppTheme.space8),
          Text(a.body, style: text.bodyMedium),
          const SizedBox(height: AppTheme.space14),
          for (final feature in missing)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    PhosphorIconsRegular.minusCircle,
                    size: AppTheme.icon18,
                    color: colors.warning,
                  ),
                  const SizedBox(width: AppTheme.space10),
                  Expanded(
                    child: Text(
                      feature.label(t),
                      style: text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppTheme.space6),
          Text(a.hint, style: text.bodySmall),
          const SizedBox(height: AppTheme.space20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(a.newSession),
          ),
        ],
      ),
    );
  }
}
