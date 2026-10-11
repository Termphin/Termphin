import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/ssh_profile.dart';
import 'ssh_session_manager_provider.dart';

/// How many sibling tabs a freshly opened terminal screen pulls in alongside
/// the session that was actually requested.
enum SiblingScope {
  /// Only the requested session - a single session row on the home screen.
  none,

  /// Every live or restorable tab that belongs to the same profile - a
  /// machine card on the home screen.
  sameProfile,

  /// Every live or restorable tab across every profile - the session dock
  /// and cold start resume whatever strip was open before, regardless of
  /// which machine each tab belongs to.
  all,
}

class TerminalOverlayNotifier
    extends Notifier<(String, SshProfile, SiblingScope)?> {
  @override
  (String, SshProfile, SiblingScope)? build() => null;

  /// This provider carries a request, not a value, and the same request can
  /// legitimately be made twice: tapping a session row for the session the
  /// overlay was last asked to show is how anyone re-opens a session they
  /// detached. Records compare structurally, so the default `previous != next`
  /// would drop that second tap on the floor, and since `MainShell` reveals
  /// the terminal only from a listener on this provider, the tap would do
  /// nothing at all.
  @override
  bool updateShouldNotify(
    (String, SshProfile, SiblingScope)? previous,
    (String, SshProfile, SiblingScope)? next,
  ) => true;

  void show(
    String sessionId,
    SshProfile profile, {
    SiblingScope scope = SiblingScope.all,
  }) {
    state = (sessionId, profile, scope);
  }

  /// What tapping a machine does, wherever it is tapped: its first live tab,
  /// else the tab whose remote session is still running, else a new one.
  /// Exactly one session - the machine's other tabs are rows of their own.
  void openProfile(SshProfile profile) {
    final manager = ref.read(sshSessionManagerProvider);
    final live = manager.getSessionsForProfile(profile.id);
    if (live.isNotEmpty) {
      final first = manager.allTabsForProfile(profile.id).first;
      show(first.id, first.profile, scope: SiblingScope.none);
      return;
    }
    show(
      manager.resumableTabIdForProfile(profile.id) ?? const Uuid().v4(),
      profile,
      scope: SiblingScope.none,
    );
  }

  void hide() {
    state = null;
  }
}

final terminalOverlayProvider =
    NotifierProvider<
      TerminalOverlayNotifier,
      (String, SshProfile, SiblingScope)?
    >(TerminalOverlayNotifier.new);
