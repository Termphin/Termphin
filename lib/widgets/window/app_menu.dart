import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/app/app_commands.dart';

/// One entry of the app's menus, shared by the title bar's and the Mac's
/// menu bar so the two list the same things.
///
/// An entry that runs an [AppCommand] shows that command's keys. One a
/// screen answers itself while it has the keyboard names them in
/// [activator], which is only ever printed: the screen's own handler is what
/// hears the key.
class AppMenuItem {
  const AppMenuItem({
    required this.label,
    required this.onSelected,
    this.icon,
    this.command,
    this.activator,
    this.enabled = true,
    this.checked,
  });

  AppMenuItem.command(
    Translations t,
    AppCommand this.command, {
    this.icon,
    String? label,
    this.enabled = true,
  }) : label = label ?? AppCommands.label(t, command),
       activator = null,
       checked = null,
       onSelected = (() => AppCommands.instance.runFromMenu(command));

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;
  final AppCommand? command;
  final SingleActivator? activator;

  /// False greys the entry out: there, so the menu does not reshuffle with
  /// every click in the list, but with nothing to act on right now.
  final bool enabled;

  /// Non-null makes the entry a switch, ticked when true.
  final bool? checked;

  /// The keys printed at the entry's end.
  SingleActivator? get shortcut =>
      activator ??
      (command == null
          ? null
          : AppCommands.activatorsFor(command!).firstOrNull);
}

class AppMenu {
  const AppMenu(this.label, this.groups);

  final String label;
  final List<List<AppMenuItem>> groups;
}

/// The menus that belong to what is on screen - a session's, the file
/// browser's, a list's - which the title bar shows between Termphin and View.
///
/// A menu bar that never changes can only hold what is true everywhere, and
/// most of what a user reaches for is not: closing a tab means nothing on
/// the machines list, a new folder nothing in a terminal. Whoever owns the
/// screen publishes its menus through a [ContextMenuScope] and takes them
/// back when it leaves.
class ContextMenus extends ChangeNotifier {
  ContextMenus._();

  static final instance = ContextMenus._();

  final _sources = <Object, List<AppMenu> Function(Translations t)>{};
  bool _notifyScheduled = false;

  List<AppMenu> build(Translations t) => [
    for (final source in _sources.values) ...source(t),
  ];

  void _set(Object owner, List<AppMenu> Function(Translations t) source) {
    _sources[owner] = source;
    refresh();
  }

  void _remove(Object owner) {
    if (_sources.remove(owner) != null) refresh();
  }

  /// Has the bar read the menus again: what they hold follows state their
  /// owner keeps - a selection, the tab in front. Deferred, because the
  /// owner usually finds out while it is building.
  void refresh() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

/// Publishes [menus] to the title bar for as long as it is mounted and
/// [active]. Rebuilding it refreshes them.
class ContextMenuScope extends StatefulWidget {
  const ContextMenuScope({
    super.key,
    required this.menus,
    required this.child,
    this.active = true,
  });

  final List<AppMenu> Function(Translations t) menus;
  final bool active;
  final Widget child;

  @override
  State<ContextMenuScope> createState() => _ContextMenuScopeState();
}

class _ContextMenuScopeState extends State<ContextMenuScope> {
  void _sync() {
    if (widget.active) {
      ContextMenus.instance._set(this, (t) => widget.menus(t));
    } else {
      ContextMenus.instance._remove(this);
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ContextMenuScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    ContextMenus.instance._remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
