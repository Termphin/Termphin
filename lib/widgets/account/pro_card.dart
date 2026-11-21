import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/pro_source.dart';
import '../../screens/pro/pro_paywall_screen.dart';
import '../../services/app/project_urls.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../ui/app_badge.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/clipboard_and_links.dart';
import '../ui/settings_tile.dart';

/// Pro, on the account screen: a plain card with a gold crown. Without Pro
/// it says in a line what Pro brings and opens the paywall; with it, says
/// thank you, with a row under a hairline - like any settings row - that
/// leads out to where the store manages the subscription. A subscription
/// bought on the web has no store to manage it: the row says so, and on a
/// desktop leads to the plan in the account on the web - on a phone it only
/// says where, a store not allowing a link to a page that sells Pro.
class ProCard extends StatefulWidget {
  const ProCard({super.key});

  @override
  State<ProCard> createState() => _ProCardState();
}

class _ProCardState extends State<ProCard> {
  ProService get _pro => ProService.instance;

  Future<void> _manage() async {
    final url = await _pro.managementUrl();
    if (url == null || !mounted) return;
    await openExternalUrl(context, Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<bool>(
      valueListenable: _pro.active,
      builder: (context, active, _) => AppCard(
        clipChild: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppTheme.space16,
                AppTheme.space16,
                AppTheme.space16,
                active ? AppTheme.space16 : AppTheme.space14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        PhosphorIconsFill.crown,
                        size: AppTheme.icon22,
                        color: colors.gold,
                      ),
                      const SizedBox(width: AppTheme.space10),
                      Text(t.account.pro.title, style: text.titleMedium),
                      if (active) ...[
                        const SizedBox(width: AppTheme.space8),
                        AppBadge(
                          t.account.pro.activeBadge,
                          tone: BadgeTone.pro,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppTheme.space8),
                  Text(
                    active
                        ? t.account.pro.activeSummary
                        : t.account.pro.summary,
                    style: text.bodyMedium,
                  ),
                  if (!active) ...[
                    const SizedBox(height: AppTheme.space14),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.gold,
                        side: BorderSide(color: colors.gold),
                      ),
                      onPressed: () => ProPaywallScreen.show(
                        context,
                        source: ProSource.account,
                      ),
                      child: Text(t.account.pro.see),
                    ),
                  ],
                ],
              ),
            ),
            if (active) ...[
              const AppDivider(),
              ValueListenableBuilder<bool>(
                valueListenable: _pro.boughtOnWeb,
                builder: (context, onWeb, _) => onWeb
                    ? SettingsTile(
                        key: const ValueKey('proBoughtOnWeb'),
                        icon: PhosphorIconsRegular.globe,
                        title: t.account.pro.boughtOnWeb,
                        subtitle: t.account.pro.boughtOnWebSubtitle,
                        trailing: platformHas(PlatformFeature.webAccountLinks)
                            ? SettingsTileTrailing.external
                            : SettingsTileTrailing.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space16,
                        ),
                        onTap: platformHas(PlatformFeature.webAccountLinks)
                            ? () => openExternalUrl(
                                context,
                                Uri.parse('${ProjectUrls.accountPage}/#plan'),
                              )
                            : null,
                      )
                    : SettingsTile(
                        title: t.account.pro.manage,
                        trailing: SettingsTileTrailing.external,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space16,
                        ),
                        onTap: _manage,
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
