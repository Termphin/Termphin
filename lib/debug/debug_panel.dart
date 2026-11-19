import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_feature.dart';
import '../models/pro_source.dart';
import '../screens/pro/pro_paywall_screen.dart';
import '../services/app/legal_updates_service.dart';
import '../services/app/onboarding_service.dart';
import '../services/app/whats_new_service.dart';
import '../services/platform/local_notifications_service.dart';
import '../services/pro/pro_hints.dart';
import '../services/pro/pro_service.dart';
import '../theme/theme.dart';
import '../widgets/onboarding/legal_update_dialog.dart';
import '../widgets/onboarding/whats_new_modal.dart';
import '../widgets/terminal/older_session_sheet.dart';
import '../widgets/terminal/terminal_rendering.dart';
import '../widgets/ui/app_notifications.dart';
import '../widgets/ui/app_sheet.dart';
import '../widgets/ui/section_header.dart';
import '../widgets/ui/settings_tile.dart';

/// A button over the app, in debug builds only, that opens a sheet of
/// everything the app shows on its own - Pro hints, the paywall, system
/// notifications, the older-helper sheet, what's new - so each can be looked
/// at without waiting for the moment it belongs to.
///
/// Built only behind `kDebugMode`, which release builds compile out with
/// everything here. Its labels are for whoever develops the app, not for
/// users, so they are not translated.
class DebugPanel extends StatefulWidget {
  const DebugPanel({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// The app's navigator, whose context the sheet and screens open on: the
  /// button sits above it, outside any route.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  Offset _position = const Offset(AppTheme.space16, 160);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: GestureDetector(
            onPanUpdate: (details) =>
                setState(() => _position += details.delta),
            onTap: _open,
            child: Container(
              width: AppTheme.icon36,
              height: AppTheme.icon36,
              decoration: BoxDecoration(
                color: context.colors.warning,
                shape: BoxShape.circle,
                boxShadow: AppTheme.floatingShadow,
              ),
              child: Icon(
                Icons.bug_report,
                size: AppTheme.icon20,
                color: context.colors.backgroundPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _open() {
    final context = widget.navigatorKey.currentContext;
    if (context == null) return;
    unawaited(
      showAppSheet<void>(
        context: context,
        builder: (sheet) => _DebugSheet(navigatorKey: widget.navigatorKey),
      ),
    );
  }
}

class _DebugSheet extends StatelessWidget {
  const _DebugSheet({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  /// Runs [action] on the app's navigator once the sheet is closed, so what
  /// it opens is not under the sheet.
  void _then(BuildContext sheet, void Function(BuildContext app) action) {
    Navigator.of(sheet).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = navigatorKey.currentContext;
      if (app != null && app.mounted) action(app);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifications = LocalNotificationsService.instance;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppTheme.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Pro hints'),
            for (final hint in ProHint.values)
              SettingsTile(
                title: 'Hint: ${hint.name}',
                subtitle:
                    'Shows the card on the machine list, ignoring once-ever and Pro',
                onTap: () => _then(context, (_) {
                  ProHints.instance.showNow(hint);
                }),
              ),
            SettingsTile(
              title: 'Forget which hints were shown',
              subtitle: 'They can come again at their moments',
              onTap: () => _then(context, (app) async {
                await ProHints.instance.forgetShown();
                if (app.mounted) {
                  AppNotifications.show(
                    app,
                    'Hints forgotten',
                    kind: AppNotificationKind.success,
                  );
                }
              }),
            ),
            const SectionHeader('Pro'),
            SettingsTile(
              title: 'Open the paywall',
              onTap: () => _then(context, (app) {
                unawaited(
                  ProPaywallScreen.show(app, source: ProSource.account),
                );
              }),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: ProService.instance.active,
              builder: (context, active, _) => SettingsTile(
                title: active ? 'Pretend no Pro' : 'Pretend Pro',
                subtitle: 'This screen only; the next refresh puts it back',
                onTap: () => ProService.instance.active.value = !active,
              ),
            ),
            const SectionHeader('System notifications'),
            SettingsTile(
              title: 'A long command finished',
              onTap: () => unawaited(
                notifications.showTerminalAlert(
                  sessionId: 'debug-finished',
                  title: 'dnf update finished',
                  body: 'Complete! · 4m 12s',
                ),
              ),
            ),
            SettingsTile(
              title: 'A program went quiet',
              onTap: () => unawaited(
                notifications.showTerminalAlert(
                  sessionId: 'debug-quiet',
                  title: 'claude went quiet',
                  body:
                      'Do you want to make this edit to cart.ts? · after 3m 5s',
                ),
              ),
            ),
            SettingsTile(
              title: "A program's own notification",
              onTap: () => unawaited(
                notifications.showTerminalAlert(
                  sessionId: 'debug-program',
                  title: 'Claude Code',
                  body: 'Claude is waiting for your input',
                ),
              ),
            ),
            SettingsTile(
              title: 'A session dropped',
              onTap: () =>
                  unawaited(notifications.showSessionDropped(name: 'api-1')),
            ),
            const SectionHeader('Terminal'),
            ValueListenableBuilder<bool>(
              valueListenable: terminalGlyphAtlas,
              builder: (context, on, _) => SettingsTile(
                title: on ? 'Glyph atlas: on' : 'Glyph atlas: off',
                subtitle: 'Off draws text as paragraphs, the old way',
                onTap: () => terminalGlyphAtlas.value = !on,
              ),
            ),
            const SectionHeader('In the app'),
            SettingsTile(
              title: 'Older helper sheet',
              subtitle: 'With every feature missing',
              onTap: () => _then(context, (app) {
                unawaited(
                  showAppSheet<bool>(
                    context: app,
                    builder: (_) =>
                        const OlderSessionSheet(missing: AgentFeature.values),
                  ),
                );
              }),
            ),
            SettingsTile(
              title: 'Show onboarding again',
              subtitle: 'On the next launch - close the app and open it',
              onTap: () => _then(context, (app) async {
                await (await SharedPreferences.getInstance()).remove(
                  kOnboardingCompletedPrefsKey,
                );
                if (app.mounted) {
                  AppNotifications.show(
                    app,
                    'Onboarding shows on the next launch',
                    kind: AppNotificationKind.success,
                  );
                }
              }),
            ),
            SettingsTile(
              title: 'Terms notice',
              subtitle: 'The latest change to the terms, as shown at launch',
              onTap: () => _then(context, (app) async {
                final update = await LegalUpdatesService.instance.latest();
                if (update != null && app.mounted) {
                  await showLegalUpdateDialog(app, update);
                }
              }),
            ),
            SettingsTile(
              title: "What's new",
              subtitle: 'Every highlight there is',
              onTap: () => _then(context, (app) async {
                final all = await WhatsNewService.instance.everyHighlight();
                if (app.mounted) await showWhatsNewModal(app, all);
              }),
            ),
            for (final kind in AppNotificationKind.values)
              SettingsTile(
                title: 'Toast: ${kind.name}',
                onTap: () => _then(context, (app) {
                  AppNotifications.show(
                    app,
                    'A ${kind.name} message, as the app shows one',
                    kind: kind,
                    actionLabel: 'Action',
                    onAction: () {},
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }
}

/// Whether the debug panel is built at all: debug builds only.
const debugPanelEnabled = kDebugMode;
