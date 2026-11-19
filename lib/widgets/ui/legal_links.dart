import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../services/app/legal_urls.dart';
import '../../theme/theme.dart';
import 'clipboard_and_links.dart';

/// The terms of service and the privacy policy, side by side as links.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: () =>
              openExternalUrl(context, Uri.parse(LegalUrls.termsOfService)),
          child: Text(t.analyticsConsent.termsLink),
        ),
        Text('·', style: TextStyle(color: colors.textTertiary)),
        TextButton(
          onPressed: () =>
              openExternalUrl(context, Uri.parse(LegalUrls.privacyPolicy)),
          child: Text(t.analyticsConsent.privacyLink),
        ),
      ],
    );
  }
}
