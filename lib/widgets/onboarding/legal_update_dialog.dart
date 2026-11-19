import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../services/app/legal_updates_service.dart';
import '../../theme/theme.dart';
import '../ui/legal_links.dart';

/// Tells someone the terms or the privacy policy changed: what changed, in
/// a sentence or two, and the links to both. Nothing to accept - "Got it"
/// is all it asks. Drawn like the what's-new popup it can sit next to.
Future<void> showLegalUpdateDialog(BuildContext context, LegalUpdate update) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LegalUpdateDialog(update: update),
    );

class LegalUpdateDialog extends StatelessWidget {
  const LegalUpdateDialog({super.key, required this.update});

  final LegalUpdate update;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: colors.surfaceElevated,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space24,
        vertical: AppTheme.space40,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        side: BorderSide(color: colors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space24,
            AppTheme.space20,
            AppTheme.space20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.legalUpdate.title,
                style: text.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppTheme.space10),
              Text(
                update.summary,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppTheme.space8),
              const LegalLinks(),
              const SizedBox(height: AppTheme.space8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t.legalUpdate.gotIt),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
