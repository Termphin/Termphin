import 'package:flutter/widgets.dart';

import '../i18n/strings.g.dart';

/// "just now" / "4m ago" / "2h ago" / "3d ago" for [moment].
///
/// Coarse on purpose: the caller is labelling when something happened, not
/// timing it, and a label that changes every second is a rebuild nobody asked
/// for.
String relativeTime(BuildContext context, DateTime moment) {
  final t = Translations.of(context);
  final elapsed = DateTime.now().difference(moment);
  if (elapsed.inMinutes < 1) return t.common.justNow;
  if (elapsed.inHours < 1) {
    return t.common.minutesAgo(minutes: elapsed.inMinutes);
  }
  if (elapsed.inDays < 1) return t.common.hoursAgo(hours: elapsed.inHours);
  return t.common.daysAgo(days: elapsed.inDays);
}
