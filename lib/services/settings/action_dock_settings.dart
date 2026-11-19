import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import 'setting.dart';

/// One entry the command palette grid can show. Fixed set, unlike the
/// toolbar's user-defined keys - what changes here is order and visibility,
/// not what the actions themselves are.
enum DockAction {
  insertSnippet,
  uploadFile,
  paste,
  search,
  copyAll,
  saveOutput,
  copyPath,
  newSession,
  tunnels,
  rename,
  viewLog,
}

/// Everything past the first four starts hidden: the palette is meant to be
/// the few tiles you actually reach for, not the whole action list. The rest
/// stay one switch away in Settings for whoever wants them.
const kDefaultHiddenDockActions = <DockAction>{
  DockAction.copyAll,
  DockAction.saveOutput,
  DockAction.copyPath,
  DockAction.newSession,
  DockAction.tunnels,
  DockAction.rename,
  DockAction.viewLog,
};

IconData dockActionIcon(DockAction action) => switch (action) {
  DockAction.insertSnippet => PhosphorIconsRegular.magicWand,
  DockAction.uploadFile => PhosphorIconsRegular.uploadSimple,
  DockAction.paste => PhosphorIconsRegular.clipboardText,
  DockAction.search => PhosphorIconsRegular.magnifyingGlass,
  DockAction.copyAll => PhosphorIconsRegular.copy,
  DockAction.saveOutput => PhosphorIconsRegular.downloadSimple,
  DockAction.copyPath => PhosphorIconsRegular.folderSimple,
  DockAction.newSession => PhosphorIconsRegular.plus,
  DockAction.tunnels => PhosphorIconsFill.arrowsLeftRight,
  DockAction.rename => PhosphorIconsRegular.pencilSimple,
  DockAction.viewLog => PhosphorIconsRegular.terminalWindow,
};

/// [DockAction.uploadFile]'s label breaks between its two words rather than
/// wherever the tile happens to wrap it, so it reads the same in every slot.
String dockActionLabel(Translations t, DockAction action) => switch (action) {
  DockAction.insertSnippet => t.commandPalette.insertSnippetTitle,
  DockAction.uploadFile => t.actionDock.uploadFile.replaceFirst(' ', '\n'),
  DockAction.paste => t.actionDock.paste,
  DockAction.search => t.actionDock.search,
  DockAction.copyAll => t.actionDock.copyAll,
  DockAction.saveOutput => t.actionDock.saveOutput,
  DockAction.copyPath => t.actionDock.copyPath,
  DockAction.newSession => t.terminal.newSession,
  DockAction.tunnels => t.portForwarding.manageTunnels,
  DockAction.rename => t.session.rename,
  DockAction.viewLog => t.connection.viewLog,
};

/// The dock's order and hidden set as one value, the shape every edit in the
/// editor takes and returns.
typedef DockLayout = ({List<DockAction> order, Set<DockAction> hidden});

/// The order the editor shows: what is on the dock first, in its order, then
/// the hidden ones. Keeping the stored order in that shape means a hidden
/// action never sits between two visible ones, where it would decide where it
/// lands once shown again without the user ever seeing that place.
List<DockAction> _normalized(List<DockAction> order, Set<DockAction> hidden) =>
    [
      for (final a in order)
        if (!hidden.contains(a)) a,
      for (final a in order)
        if (hidden.contains(a)) a,
    ];

/// [layout] with [action] on the dock at [index] among the visible actions,
/// whether it was on the dock already or hidden. The rest shift to make room,
/// so dragging a tile forward drops it after the tile it was let go on and
/// dragging it back drops it before that tile.
DockLayout placeDockAction(DockLayout layout, DockAction action, int index) {
  final hidden = {...layout.hidden}..remove(action);
  final rest = [
    for (final a in layout.order)
      if (a != action) a,
  ];
  final visible = [
    for (final a in rest)
      if (!hidden.contains(a)) a,
  ];
  visible.insert(index.clamp(0, visible.length), action);
  return (
    order: [
      ...visible,
      for (final a in rest)
        if (hidden.contains(a)) a,
    ],
    hidden: hidden,
  );
}

/// [layout] with [action] taken off the dock, at the end of the hidden ones -
/// the tray reads in the order things were put into it.
DockLayout hideDockAction(DockLayout layout, DockAction action) {
  final hidden = {...layout.hidden, action};
  final order = _normalized([
    for (final a in layout.order)
      if (a != action) a,
  ], hidden)..add(action);
  return (order: order, hidden: hidden);
}

/// What a fresh install shows.
const DockLayout kDefaultDockLayout = (
  order: DockAction.values,
  hidden: kDefaultHiddenDockActions,
);

const kActionDockOrderPrefsKey = 'command_palette_order';
const kActionDockHiddenPrefsKey = 'command_palette_hidden';

DockAction? _byName(String name) =>
    DockAction.values.where((a) => a.name == name).firstOrNull;

/// The dock's order and which entries it leaves out.
///
/// Both are stored as lists of enum names and both need their own fallback
/// rules, which is why they are built from the raw string-list setting rather
/// than from [Setting.option].
class ActionDockSettings {
  ActionDockSettings._();

  static final ActionDockSettings instance = ActionDockSettings._();

  /// An action added to the enum after this was last saved has no place in
  /// the stored order - it lands at the end rather than disappearing.
  final order = Setting<List<DockAction>>(
    key: kActionDockOrderPrefsKey,
    fallback: DockAction.values,
    read: (preferences) {
      final stored = preferences.getStringList(kActionDockOrderPrefsKey);
      if (stored == null) return DockAction.values;
      final ordered = stored.map(_byName).whereType<DockAction>().toList();
      for (final action in DockAction.values) {
        if (!ordered.contains(action)) ordered.add(action);
      }
      return ordered;
    },
    write: (preferences, value) => preferences.setStringList(
      kActionDockOrderPrefsKey,
      [for (final action in value) action.name],
    ),
  );

  /// Never saved anything yet means the defaults apply. An empty stored list
  /// is a deliberate "show everything" and must not be mistaken for that -
  /// which is exactly the distinction a plain default would lose.
  final hidden = Setting<Set<DockAction>>(
    key: kActionDockHiddenPrefsKey,
    fallback: kDefaultHiddenDockActions,
    read: (preferences) {
      final stored = preferences.getStringList(kActionDockHiddenPrefsKey);
      if (stored == null) return kDefaultHiddenDockActions;
      return stored.map(_byName).whereType<DockAction>().toSet();
    },
    write: (preferences, value) => preferences.setStringList(
      kActionDockHiddenPrefsKey,
      [for (final action in value) action.name],
    ),
  );

  List<Setting<Object?>> get all => [order, hidden];

  Future<void> load() async {
    await Future.wait([for (final setting in all) setting.load()]);
  }
}

ActionDockSettings get actionDockSettings => ActionDockSettings.instance;
