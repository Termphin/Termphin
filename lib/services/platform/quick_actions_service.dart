import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';

import '../../models/ssh_profile.dart';
import '../../utils/platform_info.dart';
import '../security/relock_guard.dart';

class QuickActionsService {
  QuickActionsService._();
  static final QuickActionsService instance = QuickActionsService._();

  final _quickActions = const QuickActions();
  String? _pendingProfileId;
  List<SshProfile> _profiles = const [];
  bool _initialized = false;

  /// Whether the app is currently able to receive a shortcut: a live
  /// navigator context exists on screen. Wired once at startup, next to
  /// [onOpenProfile] - this service holds no navigator of its own.
  bool Function()? isReady;

  /// What opens [profile] once a shortcut is actually allowed through: the
  /// same as tapping its machine on the home screen. Wired once at startup,
  /// where the navigator and the provider container live - this service
  /// knows neither.
  void Function(SshProfile profile)? onOpenProfile;

  /// Every profile-avatar icon id, in display order; the first one is the
  /// fallback for a profile whose own icon id is not among them. Wired once
  /// at startup, so this service does not need the widget that owns the
  /// icons themselves.
  List<String> iconIds = const [];

  /// Normalises a profile's colour hex to one of the avatar palette's own
  /// hexes, falling back to the palette's first colour. Wired once at
  /// startup, for the same reason as [iconIds].
  String Function(String? hex) normalizeColorHex = (_) => '';

  /// What the system was last handed, so a rebuild that changes nothing
  /// about the four machines does not hand it the same list again.
  String? _lastItems;
  bool _failureReported = false;

  /// quick_actions only ships Android and iOS implementations - there is no
  /// home screen to put a shortcut on anywhere else, so desktop is a no-op
  /// rather than a MissingPluginException.
  static bool get _supported => isAndroidPlatform || isIOSPlatform;

  void init() {
    if (_initialized || !_supported) return;
    _initialized = true;

    _quickActions.initialize((String shortcutType) {
      _handleAction(shortcutType);
    });
  }

  /// Publishes shortcuts for the four most recently used profiles.
  ///
  /// iOS icon names carry no colour, since the system tints template images
  /// itself and no per-colour assets exist there; Android's do.
  void update(List<SshProfile> profiles) {
    _profiles = profiles;
    if (!_initialized) return;

    final sorted = List<SshProfile>.from(profiles)
      ..sort((a, b) {
        final aDate = a.lastConnectedAt ?? a.createdAt;
        final bDate = b.lastConnectedAt ?? b.createdAt;
        return bDate.compareTo(aDate);
      });

    final top4 = sorted.take(4).toList();

    final items = top4.map((profile) {
      final iconName = iconIds.contains(profile.iconName)
          ? profile.iconName!
          : iconIds.first;
      final colorHex = normalizeColorHex(profile.colorHex);
      final icon = isIOSPlatform
          ? 'qa_${iconName.toLowerCase()}'
          : 'qa_${iconName.toLowerCase()}_${colorHex.toLowerCase()}';
      return ShortcutItem(
        type: profile.id,
        localizedTitle: profile.name,
        icon: icon,
      );
    }).toList();

    final signature = [
      for (final item in items)
        '${item.type}|${item.localizedTitle}|${item.icon}',
    ].join('\n');
    if (signature != _lastItems) {
      _lastItems = signature;
      unawaited(_quickActions.setShortcutItems(items).catchError(_onRefused));
    }

    _tryConsumePending();
  }

  /// Shortcuts are a convenience; a system that refuses them leaves the app
  /// without them, not broken. Reported once, so it stays visible without
  /// arriving on every launch.
  void _onRefused(Object error, StackTrace stack) {
    if (_failureReported) return;
    _failureReported = true;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'quick actions',
        context: ErrorDescription('while setting the home screen shortcuts'),
      ),
    );
  }

  void _handleAction(String profileId) {
    if (!(isReady?.call() ?? false)) {
      _pendingProfileId = profileId;
      return;
    }

    final match = _profiles.where((p) => p.id == profileId);
    if (match.isEmpty) {
      _pendingProfileId = profileId;
      return;
    }

    _openSession(match.first);
  }

  void _tryConsumePending() {
    if (_pendingProfileId == null) return;

    final match = _profiles.where((p) => p.id == _pendingProfileId);
    if (match.isEmpty) return;

    final profile = match.first;
    _pendingProfileId = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openSession(profile);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Opens [profile], the same as tapping the machine on the home screen:
  /// its open tab, or the session it left running, and a new shell only
  /// when there is neither.
  ///
  /// A shortcut is a way back into the app; one that arrives while the PIN
  /// is due again waits behind it rather than opening a shell. Checked here,
  /// not in the handler, so one parked until the machine list loaded waits
  /// too.
  void _openSession(SshProfile profile) {
    if (RelockGuard.instance.holding) {
      RelockGuard.instance.whenUnlocked(() => _openSession(profile));
      return;
    }
    onOpenProfile?.call(profile);
  }
}
