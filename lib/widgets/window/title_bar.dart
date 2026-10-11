import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/release_notes_screen.dart';
import '../../services/app/app_commands.dart';
import '../../services/app/project_urls.dart';
import '../../services/platform/desktop_window.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../ui/app_sheet.dart';
import '../ui/section_navigator.dart';
import 'window_buttons.dart';

/// Height of the app's own title bar on a desktop.
const double kTitleBarHeight = 36;

/// Room left on a Mac for the traffic lights the system draws over the bar.
const double _kMacTrafficLightsWidth = 78;

/// The title bar the app draws in place of the system's on a desktop.
///
/// What the system's had - the name, a place to drag the window by, double
/// click to maximize, the three buttons - plus what a desktop app keeps up
/// there: its menus, the path to the page on screen in place of a back arrow,
/// and the search every list starts from, with its shortcut on it.
///
/// [navigatorContext] is where the menus open pages and dialogs from: the bar
/// sits above the app's navigator, not inside it.
///
/// An unfocused window's bar steps back, as the system's did; the buttons
/// stay usable, only quieter.
class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({super.key, required this.navigatorContext});

  final BuildContext? Function() navigatorContext;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mac = isMacOSPlatform;
    return ValueListenableBuilder<bool>(
      valueListenable: DesktopWindow.instance.focused,
      builder: (context, focused, _) => AnimatedOpacity(
        opacity: focused ? 1 : 0.72,
        duration: AppTheme.interactiveDuration,
        child: Container(
          key: const ValueKey('desktopTitleBar'),
          height: kTitleBarHeight,
          decoration: BoxDecoration(
            color: colors.backgroundPrimary,
            border: Border(bottom: BorderSide(color: colors.surfaceBorder)),
          ),
          child: Row(
            children: [
              if (mac)
                const _DragArea(width: _kMacTrafficLightsWidth)
              else ...[
                const SizedBox(width: 12),
                Image.asset('assets/logo.png', width: 16, height: 16),
                const SizedBox(width: 6),
                _TitleMenus(navigatorContext: navigatorContext),
              ],
              const Expanded(child: _DragArea(child: _Breadcrumb())),
              const _SearchButton(),
              const SizedBox(width: 8),
              if (!mac) const WindowButtons() else const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a stretch of the bar the window is dragged by.
class _DragArea extends StatelessWidget {
  const _DragArea({this.width, this.child});

  final double? width;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: child ?? const SizedBox.expand(),
      ),
    );
  }
}

/// The path to the page on screen, every step but the last a link back to
/// it. The desktop's answer to a back arrow.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ValueListenableBuilder<List<BreadcrumbEntry>>(
      valueListenable: desktopBreadcrumb,
      builder: (context, entries, _) {
        if (entries.isEmpty) return const SizedBox.expand();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                key: const ValueKey('desktopBreadcrumb'),
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          PhosphorIconsRegular.caretRight,
                          size: 12,
                          color: colors.textTertiary,
                        ),
                      ),
                    _CrumbButton(
                      entry: entries[i],
                      last: i == entries.length - 1,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CrumbButton extends StatelessWidget {
  const _CrumbButton({required this.entry, required this.last});

  final BreadcrumbEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.colors.uiSmall.copyWith(
      fontSize: 12.5,
      fontWeight: last ? FontWeight.w600 : FontWeight.w500,
      color: last ? colors.textPrimary : colors.textSecondary,
    );
    final onTap = entry.onTap;
    if (onTap == null) return Text(entry.label, style: style);
    return _HoverBox(
      onTap: onTap,
      child: Text(entry.label, style: style),
    );
  }
}

/// A flat, rounded hover target - what every clickable thing in the bar is.
class _HoverBox extends StatefulWidget {
  const _HoverBox({
    super.key,
    required this.onTap,
    required this.child,
    this.filled,
    this.radius = 0,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool? filled;

  /// Square by default, like the menus they open; the search pill rounds a
  /// little to read as a field rather than a menu.
  final double radius;

  @override
  State<_HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<_HoverBox> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filled = widget.filled ?? false;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.interactiveDuration,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered
                ? colors.surfaceCard
                : filled
                ? colors.fieldFill
                : colors.surfaceCard.invisible,
            borderRadius: BorderRadius.circular(widget.radius),
            border: filled ? Border.all(color: colors.surfaceBorder) : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The search pill: what Ctrl+Shift+K opens, labelled with the keys.
class _SearchButton extends StatelessWidget {
  const _SearchButton();

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final shortcut = AppCommands.shortcutLabel(AppCommand.globalSearch) ?? '';
    return Tooltip(
      message: AppCommands.label(t, AppCommand.globalSearch),
      child: _HoverBox(
        key: const ValueKey('titleBarSearch'),
        filled: true,
        radius: 6,
        onTap: () => AppCommands.instance.run(AppCommand.globalSearch),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.magnifyingGlass,
              size: 13,
              color: colors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              t.window.search,
              style: colors.uiSmall.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(width: 18),
            Text(
              shortcut,
              style: colors.uiSmall.copyWith(
                fontSize: 11,
                color: colors.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Termphin / View / Help, off a Mac - where the same menus are the system's
/// menu bar instead (see `AppMenuBar`). Styled as a desktop menu: square,
/// tight, small type - not a phone's card.
class _TitleMenus extends StatelessWidget {
  const _TitleMenus({required this.navigatorContext});

  final BuildContext? Function() navigatorContext;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final menus = appMenuModel(t, navigatorContext);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final menu in menus)
          MenuAnchor(
            alignmentOffset: const Offset(0, 4),
            style: MenuStyle(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  side: BorderSide(color: context.colors.surfaceBorderStrong),
                ),
              ),
              backgroundColor: WidgetStatePropertyAll(
                context.colors.surfaceCard,
              ),
              elevation: const WidgetStatePropertyAll(6),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 6),
              ),
            ),
            menuChildren: [
              for (final group in menu.groups) ...[
                if (group != menu.groups.first)
                  Divider(
                    height: 13,
                    thickness: 1,
                    color: context.colors.surfaceDivider,
                  ),
                for (final item in group)
                  MenuItemButton(
                    style: MenuItemButton.styleFrom(
                      shape: const RoundedRectangleBorder(),
                      minimumSize: const Size(260, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      iconSize: 18,
                      textStyle: context.colors.uiSmall.copyWith(fontSize: 15),
                      foregroundColor: context.colors.textPrimary,
                      iconColor: context.colors.textSecondary,
                    ),
                    leadingIcon: item.icon == null
                        ? const SizedBox(width: 18)
                        : Icon(item.icon, size: 18),
                    shortcut: item.command == null
                        ? null
                        : AppCommands.activatorsFor(item.command!).firstOrNull,
                    onPressed: item.onSelected,
                    child: Text(item.label),
                  ),
              ],
            ],
            builder: (context, controller, _) => _HoverBox(
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: Text(
                menu.label,
                style: context.colors.uiSmall.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One entry of the app's menus, shared by the title bar's and the Mac's
/// menu bar so the two list the same things.
class AppMenuItem {
  const AppMenuItem({
    required this.label,
    required this.onSelected,
    this.icon,
    this.command,
  });

  AppMenuItem.command(Translations t, AppCommand this.command, {this.icon})
    : label = AppCommands.label(t, command),
      onSelected = (() => AppCommands.instance.runFromMenu(command));

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;
  final AppCommand? command;
}

class AppMenu {
  const AppMenu(this.label, this.groups);

  final String label;
  final List<List<AppMenuItem>> groups;
}

List<AppMenu> appMenuModel(
  Translations t,
  BuildContext? Function() navigatorContext,
) {
  void releaseNotes() {
    final ctx = navigatorContext();
    if (ctx == null) return;
    pushAppWindow<void>(ctx, builder: (_) => const ReleaseNotesScreen());
  }

  return [
    AppMenu(t.window.menuApp, [
      [
        AppMenuItem.command(
          t,
          AppCommand.openSettings,
          icon: PhosphorIconsRegular.gearSix,
        ),
        AppMenuItem(
          label: t.window.releaseNotes,
          icon: PhosphorIconsRegular.sparkle,
          onSelected: releaseNotes,
        ),
      ],
      [
        AppMenuItem.command(
          t,
          AppCommand.quit,
          icon: PhosphorIconsRegular.signOut,
        ),
      ],
    ]),
    AppMenu(t.window.menuView, [
      [
        AppMenuItem.command(
          t,
          AppCommand.globalSearch,
          icon: PhosphorIconsRegular.magnifyingGlass,
        ),
        AppMenuItem.command(
          t,
          AppCommand.toggleSidebar,
          icon: PhosphorIconsRegular.sidebarSimple,
        ),
      ],
      [
        AppMenuItem.command(
          t,
          AppCommand.zoomIn,
          icon: PhosphorIconsRegular.magnifyingGlassPlus,
        ),
        AppMenuItem.command(
          t,
          AppCommand.zoomOut,
          icon: PhosphorIconsRegular.magnifyingGlassMinus,
        ),
        AppMenuItem.command(
          t,
          AppCommand.zoomReset,
          icon: PhosphorIconsRegular.textAa,
        ),
      ],
    ]),
    AppMenu(t.window.menuHelp, [
      [
        AppMenuItem.command(
          t,
          AppCommand.openManual,
          icon: PhosphorIconsRegular.bookOpen,
        ),
        AppMenuItem.command(
          t,
          AppCommand.showShortcuts,
          icon: PhosphorIconsRegular.keyboard,
        ),
      ],
      [
        AppMenuItem(
          label: t.window.reportIssue,
          icon: PhosphorIconsRegular.bug,
          onSelected: () => launchUrl(
            Uri.parse(ProjectUrls.issues),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
    ]),
  ];
}

/// The Mac's own menu bar, carrying the same menus as the title bar does
/// elsewhere. A Mac app with nothing but the system's default menu reads as
/// unfinished, and the menu bar is where a Mac user looks for the shortcuts:
/// each item shows its command's key equivalent. Should the same keystroke
/// also reach the keyboard handler, `runFromMenu` runs it once.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({
    super.key,
    required this.navigatorContext,
    required this.child,
  });

  final BuildContext? Function() navigatorContext;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!platformHas(PlatformFeature.nativeMenuBar)) return child;
    final t = Translations.of(context);
    final model = appMenuModel(t, navigatorContext);
    return PlatformMenuBar(
      menus: [
        for (final menu in model)
          PlatformMenu(
            label: menu.label,
            menus: [
              for (final group in menu.groups)
                PlatformMenuItemGroup(
                  members: [
                    for (final item in group)
                      PlatformMenuItem(
                        label: item.label,
                        shortcut: item.command == null
                            ? null
                            : AppCommands.activatorsFor(
                                item.command!,
                              ).firstOrNull,
                        onSelected: item.onSelected,
                      ),
                  ],
                ),
            ],
          ),
      ],
      child: child,
    );
  }
}
