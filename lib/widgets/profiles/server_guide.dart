import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/app/manual_urls.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/app_sheet.dart';
import '../ui/manual_link.dart';

/// Where a server can come from, for someone who has none.
///
/// Most people who install and never connect do not have a machine to connect
/// to - or expected a terminal on the phone itself - so the empty machine list
/// and the first-run flow both say where one comes from rather than only
/// offering a form.
class ServerGuideList extends StatelessWidget {
  const ServerGuideList({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return AppCard.fields(
      children: [
        _GuideRow(
          icon: PhosphorIconsRegular.desktop,
          title: t.serverGuide.computerTitle,
          body: t.serverGuide.computerBody,
          page: ManualPage.enableSsh,
        ),
        const AppDivider(),
        _GuideRow(
          icon: PhosphorIconsRegular.cloud,
          title: t.serverGuide.cloudTitle,
          body: t.serverGuide.cloudBody,
          page: ManualPage.cloudServer,
        ),
      ],
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.page,
  });

  final IconData icon;
  final String title;
  final String body;

  /// The manual's step-by-step for this way of getting a server.
  final ManualPage page;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => openManual(context, page),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: colors.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: colors.itemTitle),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: colors.uiSmall.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Translations.of(context).manual.readMore,
                    style: colors.uiSmall.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The guide as a sheet, from the empty machine list.
Future<void> showServerGuideSheet(BuildContext context) {
  unawaited(AnalyticsService.instance.screen(AnalyticsScreen.serverGuide));
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) {
      final t = Translations.of(sheetContext);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.serverGuide.title,
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            const ServerGuideList(),
          ],
        ),
      );
    },
  );
}
