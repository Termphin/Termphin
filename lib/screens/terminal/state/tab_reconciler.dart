import '../../../services/ssh/ssh_session_manager.dart';

/// Decides which of the strip's tabs have been closed somewhere other than the
/// strip - the home screen's session row menu is the one that matters.
///
/// Extracted from `TerminalScreen` for the same reason [SessionSwipeController]
/// and [KeyboardInsetController] were: it is a rule, not a piece of layout, and
/// while it lived on the widget the only way to exercise it was to build a
/// terminal, an SFTP browser and a connection alongside it. It is also the part
/// that goes wrong, so it is the part that has to be cheap to test.
///
/// The whole difficulty is telling "this tab is gone" from "this tab is not
/// registered *yet*". A tab the strip has just added sits in its list a moment
/// before `startSession` registers it with the manager, and during that gap the
/// manager will happily report it as absent. [_known] is what closes that gap:
/// only ids the manager has already acknowledged can be dropped.
class TabReconciler {
  TabReconciler(this._manager);

  final SshSessionManager _manager;

  /// Tab ids the manager has actually *held* at least once.
  ///
  /// Held, not merely mentioned. A detached session stays in `tabs` - that is
  /// what makes it resumable - so acknowledging everything the manager lists
  /// would put a detached id straight back in here the moment it is re-added
  /// to the strip, defeating [forget] and the gap it protects.
  final Set<String> _known = {};

  /// A tab must be held *and* established before it counts. `startSession`
  /// registers its session object and notifies before the handshake, so a
  /// tab acknowledged on that notification alone would be eligible for
  /// pruning the moment the connection fails - which takes the strip's error
  /// card away with it, and an empty strip closes the terminal outright. A
  /// tab record only exists once a handshake has finished, so it is what
  /// tells a connection that failed from one that was closed somewhere else.
  void _acknowledgeHeld() {
    for (final session in _manager.tabs) {
      if (_manager.stripHoldsTab(session.id) &&
          _manager.tabIsEstablished(session.id)) {
        _known.add(session.id);
      }
    }
  }

  /// Seeded up front rather than left to the first notification: ending a tab
  /// drops it from `tabs` outright, so a strip that had not seen a manager
  /// change yet would never learn the id and would keep the dead tab.
  void seed() => _acknowledgeHeld();

  /// Drops [ids] back to "never acknowledged".
  ///
  /// Every removal from the strip has to come through here. A detached session
  /// keeps its id, so opening it again re-adds that same id - and an id still
  /// sitting in [_known] is eligible for pruning from the moment it is re-added,
  /// which is precisely the gap [_known] exists to protect. Leaving it behind
  /// means the session connects and is then pulled straight back out of the
  /// strip, which reads as the tap having done nothing.
  void forget(Iterable<String> ids) => _known.removeAll(ids);

  /// Which of [stripTabIds] the manager says are gone.
  Set<String> closedElsewhere(Iterable<String> stripTabIds) {
    _acknowledgeHeld();
    return stripTabIds
        .where((id) => _known.contains(id) && !_manager.stripHoldsTab(id))
        .toSet();
  }
}
