import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/app/version_compare.dart';
import '../../theme/theme.dart';
import 'app_badge.dart';

/// Whether a row marked new until [until] still gets its badge in
/// [appVersion]. Unknown or unparseable versions show nothing.
bool isStillNew(String? appVersion, String until) {
  if (appVersion == null || !isReleasedVersion(appVersion)) return false;
  return compareVersions(appVersion, until) < 0;
}

/// "New" beside a settings row, gone by itself once the app reaches [until]
/// - the last one was hand-placed with a TODO to remove it and outlived it.
class NewBadge extends StatelessWidget {
  const NewBadge({super.key, required this.appVersion, required this.until});

  final String? appVersion;
  final String until;

  @override
  Widget build(BuildContext context) {
    if (!isStillNew(appVersion, until)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: AppTheme.space8),
      child: AppBadge(
        Translations.of(context).settings.newBadge,
        tone: BadgeTone.accent,
      ),
    );
  }
}
