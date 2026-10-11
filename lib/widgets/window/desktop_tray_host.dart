import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/ssh_session_manager_provider.dart';
import '../../providers/terminal_overlay_provider.dart';
import '../../services/app/app_commands.dart';
import '../../services/platform/desktop_tray.dart';
import '../../services/platform/desktop_window.dart';
import '../../services/platform/tray_menu.dart';
import '../../services/settings/desktop_settings.dart';
import '../../services/ssh/ssh_session_manager.dart';

/// Whether the first close has asked what closing should do. Device state:
/// the answer itself is [closeToTraySetting], which is backed up.
const kCloseAskedPrefsKey = 'desktop_close_asked';

/// Owns what happens around the window on a desktop: the tray icon and its
/// menu, closing into the tray rather than quitting, and quitting itself.
class DesktopTrayHost extends ConsumerStatefulWidget {
  const DesktopTrayHost({
    super.key,
    required this.navigatorContext,
    required this.child,
    this.tray,
    this.window,
    this.manager,
  });

  /// Where the close and quit dialogs open - the app's navigator, which this
  /// sits outside of.
  final BuildContext? Function() navigatorContext;
  final Widget child;

  @visibleForTesting
  final DesktopTray? tray;
  @visibleForTesting
  final DesktopWindowControls? window;
  @visibleForTesting
  final SshSessionManager? manager;

  @override
  ConsumerState<DesktopTrayHost> createState() => _DesktopTrayHostState();
}

/// The part of [DesktopWindow] this host drives, so a test can stand in.
abstract class DesktopWindowControls {
  set onCloseRequested(Future<void> Function()? handler);
  Future<void> show();
  Future<void> hide();
  Future<void> quit();
}

class _RealWindow implements DesktopWindowControls {
  const _RealWindow();

  @override
  set onCloseRequested(Future<void> Function()? handler) =>
      DesktopWindow.instance.onCloseRequested = handler;

  @override
  Future<void> show() => DesktopWindow.instance.show();

  @override
  Future<void> hide() => DesktopWindow.instance.hide();

  @override
  Future<void> quit() => DesktopWindow.instance.quit();
}

class _DesktopTrayHostState extends ConsumerState<DesktopTrayHost> {
  late final DesktopTray _tray = widget.tray ?? DesktopTray.instance;
  late final DesktopWindowControls _window =
      widget.window ?? const _RealWindow();
  late final SshSessionManager _manager =
      widget.manager ?? ref.read(sshSessionManagerProvider);

  VoidCallback? _unregisterQuit;
  bool _refreshQueued = false;
  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    _window.onCloseRequested = _onCloseRequested;
    _unregisterQuit = AppCommands.instance.register(AppCommand.quit, (_) {
      unawaited(_quit());
      return true;
    });
    _manager.addListener(_queueRefresh);
    closeToTraySetting.addListener(_queueRefresh);
    _queueRefresh();
  }

  @override
  void dispose() {
    _window.onCloseRequested = null;
    _unregisterQuit?.call();
    _manager.removeListener(_queueRefresh);
    closeToTraySetting.removeListener(_queueRefresh);
    super.dispose();
  }

  /// Sessions change in bursts - a reconnect is several notifications - and
  /// the menu only needs to be right once they settle.
  void _queueRefresh() {
    if (_refreshQueued) return;
    _refreshQueued = true;
    scheduleMicrotask(() {
      _refreshQueued = false;
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (!closeToTraySetting.value) {
      await _tray.hide();
      return;
    }
    final t = Translations.of(context);
    final connected = _manager.activeSessions;
    await _tray.show(
      tooltip: t.window.trayTooltip(n: connected.length),
      menu: buildTrayMenu(
        t: t,
        connected: connected,
        profiles: ref.read(profilesProvider),
        anonymize: ref.read(anonymizeProvider),
        onShow: () => unawaited(_window.show()),
        onOpenSession: _openSession,
        onNewSession: _newSession,
        onQuit: () => unawaited(_quit()),
      ),
      onActivate: () => unawaited(_window.show()),
    );
  }

  void _openSession(ActiveSessionView session) {
    unawaited(_window.show());
    ref
        .read(terminalOverlayProvider.notifier)
        .show(session.id, session.profile, scope: SiblingScope.none);
  }

  void _newSession(SshProfile profile) {
    unawaited(_window.show());
    ref
        .read(terminalOverlayProvider.notifier)
        .show(const Uuid().v4(), profile, scope: SiblingScope.none);
  }

  /// The window's close button, or the system's. Into the tray when there is
  /// one and the setting says so; the first time, it asks.
  Future<void> _onCloseRequested() async {
    if (!await _tray.available) return _quit();
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(kCloseAskedPrefsKey) ?? false)) {
      final keep = await _askKeepRunning();
      if (keep == null) return;
      await prefs.setBool(kCloseAskedPrefsKey, true);
      await closeToTraySetting.set(keep);
      if (!keep) return _quit(confirmed: true);
    }
    if (closeToTraySetting.value) {
      await _window.hide();
    } else {
      await _quit();
    }
  }

  Future<bool?> _askKeepRunning() async {
    final ctx = widget.navigatorContext();
    if (ctx == null) return true;
    final t = Translations.of(ctx);
    return showDialog<bool>(
      context: ctx,
      builder: (dialog) => AlertDialog(
        title: Text(t.window.closeAskTitle),
        content: Text(t.window.closeAskBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(t.window.closeAskQuit),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(t.window.closeAskKeep),
          ),
        ],
      ),
    );
  }

  /// Ends the app - after saying what it ends, when sessions are connected.
  Future<void> _quit({bool confirmed = false}) async {
    if (_quitting) return;
    final live = _manager.activeSessions.length;
    if (!confirmed && live > 0) {
      await _window.show();
      final ctx = widget.navigatorContext();
      if (ctx == null || !ctx.mounted) return;
      final t = Translations.of(ctx);
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (dialog) => AlertDialog(
          title: Text(t.window.quitConfirmTitle),
          content: Text(t.window.quitConfirmBody(n: live)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(t.common.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(t.window.quitConfirm),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    _quitting = true;
    await _tray.hide();
    await _window.quit();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(profilesProvider, (_, _) => _queueRefresh());
    ref.listen(anonymizeProvider, (_, _) => _queueRefresh());
    return widget.child;
  }
}
