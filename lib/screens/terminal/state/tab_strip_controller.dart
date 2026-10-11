import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../models/ssh_profile.dart';
import '../../../services/ssh/ssh_session_manager.dart' show SavedSplit;
import '../../../widgets/terminal/session_view.dart' show SessionViewMode;
import 'tab_splits.dart';

const _uuid = Uuid();

/// Owns the tab strip's pure state: the open sessions, which one is active,
/// each tab's view mode, when each last had focus, and the splits between
/// them.
///
/// Lifted out of `TerminalScreenState`, which held all of this as fields
/// alongside everything that touches `BuildContext`, `ref` and the session
/// manager - this holds none of that, so it is cheap to exercise without
/// building a terminal at all. A mutation ends in exactly one
/// [notifyListeners] call, except [noteFocus] on its own, which never
/// notifies: in the screen it never triggered a rebuild by itself, only ever
/// alongside another state change in the same gesture.
class TabStripController extends ChangeNotifier {
  TabStripController({
    required List<(String, SshProfile)> sessions,
    required int activeIndex,
  }) : _sessions = List.of(sessions),
       _activeIndex = activeIndex;

  final List<(String, SshProfile)> _sessions;
  int _activeIndex;

  /// Terminal or SFTP is a property of the tab, not of the screen: one tab
  /// sitting in a file browser says nothing about what the next one should
  /// show.
  final Map<String, SessionViewMode> _viewModes = {};

  /// When each tab last had focus, so a split comes back with the pane that
  /// was focused when it was left.
  final Map<String, int> _focusedAt = {};
  int _focusClock = 0;

  final TabSplits _splits = TabSplits();

  List<(String, SshProfile)> get sessions => UnmodifiableListView(_sessions);

  int get activeIndex => _activeIndex;

  (String, SshProfile) get active => _sessions[_activeIndex];

  List<String> get sessionIds => [for (final s in _sessions) s.$1];

  /// The strip's entries - a split is one, holding both of its sessions.
  List<List<String>> get entries => _splits.entries(sessionIds);

  int entryIndexOf(String sessionId) =>
      entries.indexWhere((entry) => entry.contains(sessionId));

  SessionViewMode modeFor(String sessionId) =>
      _viewModes[sessionId] ?? SessionViewMode.terminal;

  String focusOf(List<String> entry) => entry.reduce(
    (a, b) => (_focusedAt[b] ?? 0) > (_focusedAt[a] ?? 0) ? b : a,
  );

  double ratioOf(String id) => _splits.ratioOf(id);

  bool isSplit(String id) => _splits.isSplit(id);

  bool canJoin(String other, String target) => _splits.canJoin(other, target);

  /// Every split among [ids], for the caller to persist.
  List<SavedSplit> saved(List<String> ids) => _splits.saved(ids);

  void noteFocus(String sessionId) => _focusedAt[sessionId] = ++_focusClock;

  void setMode(String sessionId, SessionViewMode mode) {
    if (modeFor(sessionId) == mode) return;
    _viewModes[sessionId] = mode;
    notifyListeners();
  }

  /// Puts [_sessions] in [ids]' order, keeping the focused tab focused.
  void _applyOrder(List<String> ids) {
    final activeId = _sessions[_activeIndex].$1;
    final byId = {for (final s in _sessions) s.$1: s};
    final reordered = [for (final id in ids) byId[id]!];
    _sessions
      ..clear()
      ..addAll(reordered);
    _activeIndex = _sessions.indexWhere((s) => s.$1 == activeId);
  }

  /// Selects [sessionId]: null when it is not open, false when it was
  /// already active, true when the active tab actually changed.
  bool? select(String sessionId) {
    final index = _sessions.indexWhere((item) => item.$1 == sessionId);
    if (index < 0) return null;
    noteFocus(sessionId);
    if (index == _activeIndex) return false;
    _activeIndex = index;
    notifyListeners();
    return true;
  }

  /// A swipe that settled on [entryIndex]. Unlike [select], this always
  /// moves and always notifies - the gesture only commits on an entry other
  /// than the active one.
  String selectEntry(int entryIndex) {
    final id = focusOf(entries[entryIndex]);
    noteFocus(id);
    _activeIndex = sessionIds.indexOf(id);
    notifyListeners();
    return id;
  }

  /// Adds [profile] as a new tab, optionally reusing [sessionId] and
  /// optionally landing it split with [splitWith]. Returns the id used.
  String add(SshProfile profile, {String? sessionId, String? splitWith}) {
    final id = sessionId ?? _uuid.v4();
    noteFocus(id);
    _sessions.add((id, profile));
    _activeIndex = _sessions.length - 1;
    if (splitWith != null && _sessions.any((s) => s.$1 == splitWith)) {
      _applyOrder(_splits.join(sessionIds, id, splitWith));
    }
    notifyListeners();
    return id;
  }

  /// Takes [ids] out of the strip and repairs the selection around them -
  /// shared by the strip's own close/detach path and by a tab closed
  /// elsewhere, so a tab removed from the home screen leaves exactly the way
  /// one removed from the tab's own menu does.
  ///
  /// [persist] runs once the splits are forgotten but before the sessions
  /// themselves are removed, so the caller still sees [ids] in [sessionIds]
  /// at that point - which is what it needs to drop their persisted splits
  /// too.
  void dropTabs(Set<String> ids, {required VoidCallback persist}) {
    final index = _sessions.indexWhere((item) => ids.contains(item.$1));
    if (index < 0) return;
    final activeId = _sessions[_activeIndex].$1;
    _splits.forget(ids);
    persist();
    for (final id in ids) {
      _viewModes.remove(id);
      _focusedAt.remove(id);
    }
    _sessions.removeWhere((item) => ids.contains(item.$1));
    if (_sessions.isNotEmpty) {
      final previousActiveIndex = _sessions.indexWhere(
        (item) => item.$1 == activeId,
      );
      _activeIndex = previousActiveIndex >= 0
          ? previousActiveIndex
          : math.min(index, _sessions.length - 1);
    }
    notifyListeners();
  }

  /// Drops a tab that was pulled into the strip automatically and then
  /// failed to ever connect. Unlike [dropTabs], [persist] here runs after
  /// the session is removed, since the caller only needs the splits dropped
  /// for this one id, not the ones [ids] still holds in [sessionIds].
  void forgetFailedRestore(String sessionId, {required VoidCallback persist}) {
    final index = _sessions.indexWhere((item) => item.$1 == sessionId);
    if (index < 0) return;
    final activeId = _sessions[_activeIndex].$1;
    _viewModes.remove(sessionId);
    _focusedAt.remove(sessionId);
    _splits.forget([sessionId]);
    _sessions.removeAt(index);
    persist();
    if (_sessions.isNotEmpty) {
      final previousActiveIndex = _sessions.indexWhere(
        (item) => item.$1 == activeId,
      );
      _activeIndex = previousActiveIndex >= 0
          ? previousActiveIndex
          : math.min(index, _sessions.length - 1);
    }
    notifyListeners();
  }

  /// A drag in the strip moves an entry, so a split moves as one.
  List<String> reorder(int oldIndex, int newIndex) {
    final ids = _splits.reorder(sessionIds, oldIndex, newIndex);
    _applyOrder(ids);
    notifyListeners();
    return ids;
  }

  /// Splits [target] with [other], which lands beside it.
  List<String> split(String other, String target) {
    final ids = _splits.join(sessionIds, other, target);
    _applyOrder(ids);
    notifyListeners();
    return ids;
  }

  List<String> swap(String sessionId) {
    final ids = _splits.swap(sessionIds, sessionId);
    _applyOrder(ids);
    notifyListeners();
    return ids;
  }

  void unsplit(String sessionId) {
    _splits.detach(sessionId);
    notifyListeners();
  }

  void setRatio(String id, double ratio) {
    _splits.setRatio(id, ratio);
    notifyListeners();
  }

  /// Puts back the splits the strip last had, where both tabs made it back.
  /// A pair naming an id that is not open is left alone. Returns whether the
  /// session order actually changed, which is when the caller has to tell
  /// the manager about the new order.
  bool restoreSplits(List<SavedSplit> savedSplits) {
    final before = sessionIds;
    for (final split in savedSplits) {
      final ids = sessionIds;
      if (!ids.contains(split.first) || !ids.contains(split.second)) continue;
      _applyOrder(_splits.join(ids, split.second, split.first));
      _splits.setRatio(split.first, split.ratio);
    }
    final changed = !listEquals(before, sessionIds);
    if (changed) notifyListeners();
    return changed;
  }
}
