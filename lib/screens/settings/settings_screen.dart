import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/pro_source.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../../widgets/assistant/phin_badges.dart';
import '../../widgets/settings/account_settings_section.dart';
import '../../widgets/settings/appearance_settings_section.dart';
import '../../widgets/settings/connection_settings_section.dart';
import '../../widgets/settings/notifications_settings_section.dart';
import '../../widgets/ui/app_badge.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/app_search_field.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/new_badge.dart';
import '../../widgets/ui/section_navigator.dart';
import '../../widgets/ui/settings_tile.dart';
import '../../widgets/window/app_menu.dart';
import '../backup/export_screen.dart';
import '../groups/groups_screen.dart';
import '../pro/pro_features_screen.dart';
import '../pro/pro_paywall_screen.dart';
import 'notifications_settings_screen.dart';
import 'phin_settings_screen.dart';
import 'settings_categories.dart';
import 'settings_search.dart';

/// Settings: the account and the theme, then one row per category, each
/// opening a screen of its own. Everything used to sit on this one screen,
/// some forty rows long; what is left here is what tells the user where to
/// go - and a search over every setting, for when they do not know.
///
/// The only thing this screen loads itself is the package info the About
/// screen's version and the "New" badges need.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  String? _version;

  /// Bare "1.9.0", for [NewBadge]; [_version] carries the build number.
  String? _appVersion;

  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = '${packageInfo.version} (${packageInfo.buildNumber})';
      _appVersion = packageInfo.version;
      _loading = false;
    });
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  /// A result on Settings itself only needs the search gone to be seen; one
  /// elsewhere opens its screen at it, and the search stays as it was for
  /// the way back.
  void _openResult(SettingsSearchEntry entry) {
    final open = entry.open;
    if (open == null) {
      FocusScope.of(context).unfocus();
      _clearSearch();
      return;
    }
    pushAppPage<void>(
      context,
      window: true,
      title: entry.title,
      builder: (_) => open(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final searching = _query.trim().isNotEmpty;
    return SectionMenus(
      menus: (t) => [
        AppMenu(t.window.menuSettings, [
          [
            for (final category in SettingsCategory.values)
              AppMenuItem(
                label: category.title(t),
                onSelected: () => pushAppPage<void>(
                  context,
                  window: true,
                  title: category.title(t),
                  builder: (_) => category.screen(t),
                ),
              ),
          ],
        ]),
      ],
      child: LargeTitleScaffold(
        title: t.settings.title,
        bodyBuilder: (context, scrollController, gutter) => _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space16,
                  0,
                  AppTheme.space16,
                  AppTheme.space32,
                ).add(gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LargeTitleHeader(
                      title: t.settings.title,
                      subtitle: t.settings.subtitle,
                      padding: const EdgeInsets.only(
                        top: AppTheme.space24,
                        bottom: AppTheme.space8,
                      ),
                    ),
                    const SizedBox(height: AppTheme.space8),
                    AppSearchField(
                      controller: _search,
                      hint: t.settings.searchHint,
                      clearTooltip: t.common.clearSearch,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: AppTheme.space16),
                    if (searching) _results(t) else ..._categories(t),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _results(Translations t) {
    final found = settingsSearchIndex(
      t,
      appVersion: _appVersion,
      version: _version,
    ).where((entry) => entry.matches(_query)).toList();
    if (found.isEmpty) {
      return EmptyStatePanel(
        icon: PhosphorIconsRegular.magnifyingGlass,
        title: t.settings.searchEmpty(query: _query.trim()),
        compact: true,
      );
    }
    return AppCard.fields(
      children: [
        for (final (index, entry) in found.indexed) ...[
          if (index > 0) const AppDivider(),
          SettingsTile(
            title: entry.title,
            subtitle: entry.place,
            onTap: () => _openResult(entry),
          ),
        ],
      ],
    );
  }

  List<Widget> _categories(Translations t) {
    SettingsTile category(SettingsCategory category, IconData icon) =>
        SettingsTile(
          icon: icon,
          title: category.title(t),
          subtitle: category.subtitle(t),
          destination: () =>
              category.screen(t, appVersion: _appVersion, version: _version),
        );

    return [
      const AccountSettingsSection(),
      const AppearanceSettingsSection(),
      const SizedBox(height: AppTheme.space20),
      AppCard.fields(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: ProService.instance.active,
            builder: (context, pro, _) => SettingsTile(
              key: const ValueKey('settingsProHub'),
              icon: PhosphorIconsRegular.crownSimple,
              iconColor: context.colors.gold,
              title: t.proHub.row,
              titleTrailing: pro
                  ? Padding(
                      padding: const EdgeInsets.only(left: AppTheme.space8),
                      child: AppBadge(t.proHub.active, tone: BadgeTone.pro),
                    )
                  : null,
              subtitle: t.proHub.rowSubtitle,
              destination: pro
                  ? () => ProFeaturesScreen(appVersion: _appVersion)
                  : null,
              onTap: pro
                  ? null
                  : () => unawaited(
                      ProPaywallScreen.show(
                        context,
                        source: ProSource.settings,
                      ),
                    ),
            ),
          ),
          const AppDivider(),
          SettingsTile(
            icon: PhosphorIconsRegular.bell,
            title: t.settings.notificationsSection,
            titleTrailing: NewBadge(
              appVersion: _appVersion,
              until: kNotificationsNewUntil,
            ),
            subtitle: t.settings.notificationsRowSubtitle,
            destination: () =>
                NotificationsSettingsScreen(appVersion: _appVersion),
          ),
          const AppDivider(),
          SettingsTile(
            icon: PhosphorIconsRegular.sparkle,
            title: t.assistant.settingsTitle,
            titleTrailing: const PhinBadges(),
            subtitle: t.assistant.settingsSubtitle,
            destination: () => const PhinSettingsScreen(),
          ),
          const AppDivider(),
          category(
            SettingsCategory.terminal,
            PhosphorIconsRegular.terminalWindow,
          ),
          const AppDivider(),
          category(SettingsCategory.files, PhosphorIconsRegular.folderOpen),
          const AppDivider(),
          const _ConnectionRow(),
          const AppDivider(),
          SettingsTile(
            icon: PhosphorIconsRegular.folders,
            title: t.groups.title,
            subtitle: t.settings.groupsSubtitle,
            destination: () => const GroupsScreen(),
          ),
        ],
      ),
      const SizedBox(height: AppTheme.space20),
      AppCard.fields(
        children: [
          category(SettingsCategory.privacy, PhosphorIconsRegular.shieldCheck),
          const AppDivider(),
          SettingsTile(
            icon: PhosphorIconsRegular.archive,
            title: t.exportScreen.title,
            subtitle: t.settings.exportImportSubtitle,
            destination: () => const ExportScreen(),
          ),
        ],
      ),
      const SizedBox(height: AppTheme.space20),
      AppCard.fields(
        children: [
          category(SettingsCategory.help, PhosphorIconsRegular.lifebuoy),
          const AppDivider(),
          category(SettingsCategory.about, PhosphorIconsRegular.info),
        ],
      ),
    ];
  }
}

/// The row into Connection, with a warning count while any permission it
/// lists is not given: those are system-owned and change behind the app's
/// back, so the count is read again on the way back from that screen and
/// whenever the app returns to the front.
class _ConnectionRow extends StatefulWidget {
  const _ConnectionRow();

  @override
  State<_ConnectionRow> createState() => _ConnectionRowState();
}

class _ConnectionRowState extends State<_ConnectionRow>
    with WidgetsBindingObserver {
  int _issues = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final issues = await connectionIssueCount();
    if (mounted) setState(() => _issues = issues);
  }

  Future<void> _open() async {
    final t = Translations.of(context);
    await pushAppPage<void>(
      context,
      window: true,
      title: t.settings.connection,
      builder: (_) => SettingsCategory.connection.screen(t),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return SettingsTile(
      icon: PhosphorIconsRegular.plugs,
      title: t.settings.connection,
      titleTrailing: _issues > 0
          ? AppBadge.count(_issues, tone: BadgeTone.warning)
          : null,
      subtitle: t.settings.connectionRowSubtitle,
      onTap: _open,
    );
  }
}
