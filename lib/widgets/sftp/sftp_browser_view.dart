import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../screens/sftp/sftp_editor_screen.dart';
import '../../screens/sftp/sftp_image_preview_screen.dart';
import '../../services/app/app_commands.dart';
import '../../services/settings/sftp_settings.dart';
import '../../services/sftp/cancel_token.dart';
import '../../services/sftp/download_service.dart';
import '../../services/sftp/remote_path.dart';
import '../../services/sftp/sftp_remote_ops.dart';
import '../../services/sftp/sftp_service.dart';
import '../../theme/theme.dart';
import '../../utils/file_type.dart';
import '../../utils/platform_info.dart';
import '../../utils/sftp_error_handler.dart';
import '../../utils/sftp_path.dart';
import '../../utils/text_sniffer.dart';
import '../terminal/terminal_scheme_theme.dart';
import '../ui/app_dropdown.dart';
import '../ui/app_notifications.dart';
import '../ui/app_sheet.dart';
import '../ui/clipboard_and_links.dart';
import '../ui/confirm_dialog.dart';
import '../ui/context_menu.dart';
import '../ui/shortcut_hint.dart';
import '../ui/text_input_dialog.dart';
import '../window/app_menu.dart';
import 'sftp_file_actions_menu.dart';
import 'sftp_file_row.dart';
import 'sftp_folder_picker.dart';
import 'sftp_path_bar.dart';
import 'sftp_selection_bar.dart';
import 'sftp_shortcuts.dart';
import 'sftp_sort_sheet.dart';
import 'transfer_conflict_dialog.dart';
import 'transfer_progress_dialog.dart';

enum _AddAction { upload, newFolder, newFile }

class SftpBrowserView extends StatefulWidget {
  const SftpBrowserView({
    super.key,
    required this.session,
    this.terminalDirectory,
  });
  final ActiveSessionView session;

  /// The directory the session's shell is in, in SFTP form, or null when it
  /// is not known or not wanted. Opened first, then again by
  /// [SftpBrowserViewState.followTerminal].
  final Future<String?> Function()? terminalDirectory;

  @override
  State<SftpBrowserView> createState() => SftpBrowserViewState();
}

class SftpBrowserViewState extends State<SftpBrowserView> {
  SftpService? _sftp;
  List<SftpName> _items = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _currentPath = '.';

  /// The terminal's directory the browser last went to, so coming back to it
  /// only moves when the shell has moved since.
  String? _followedDirectory;
  String _error = '';
  final List<String> _history = [];
  bool _showHidden = sftpShowHiddenSetting.value;

  /// Mirrors [SftpPathBar]'s own editing state, just so the list below it can
  /// grow a tap-to-unfocus catcher while a path is being typed.
  bool _editingPath = false;

  SftpSortField _sortField = SftpSortField.name;
  bool _sortDescending = false;

  /// Bumped by every call to [_loadDirectory], so a load that resolves after
  /// a newer one has already started can tell it is stale and drop its
  /// result instead of overwriting what the newer load put up.
  int _loadGeneration = 0;

  final Set<String> _selected = {};

  /// Whether the selection has the bar of its own in place of the path bar.
  ///
  /// On a phone that is any selection: it starts with a long press and means
  /// the user is picking. On a desktop a click selects, as in a file manager,
  /// so one selected row is the ordinary state of the listing - the path bar
  /// stays, and the bar for the selection comes with the second row.
  bool get _selectionMode =>
      isDesktopPlatform ? _selected.length > 1 : _selected.isNotEmpty;

  /// The last few copy and move destinations per machine, for the picker.
  /// Memory only: a folder picked last week is as likely gone as useful.
  static final Map<String, List<String>> _recentDestinations = {};

  @visibleForTesting
  static void clearRecentDestinations() => _recentDestinations.clear();

  /// What the server is doing for a copy or move, shown under the path bar.
  String? _busyLabel;
  bool get _transferring => _busyLabel != null;

  /// A copy runs `cp` on the server; an account locked to SFTP has no way to.
  bool get _copyAvailable => _sftp?.canRunCommands != false;

  /// Content sniffing results, keyed by path - one read per file per listing.
  final Map<String, TextProbe> _textProbes = {};

  /// Paths currently being sniffed, so two rows probed at once each keep
  /// their own spinner rather than sharing one that whichever finishes first
  /// clears for both.
  final Set<String> _probingPaths = {};

  /// One per row, keyed by path, so its actions menu can be opened
  /// programmatically - tapping a file that turns out to be binary opens the
  /// same menu its own `⋮` button would, rather than a second, separate one.
  final Map<String, ValueNotifier<Object?>> _fileMenuOpeners = {};

  ValueNotifier<Object?> _menuOpenerFor(String path) =>
      _fileMenuOpeners.putIfAbsent(path, () => ValueNotifier(null));

  Color get _background => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _border => Theme.of(context).dividerColor;
  Color get _textPrimary => Theme.of(context).colorScheme.onSurface;
  Color get _textSecondary =>
      Theme.of(context).textTheme.bodyMedium?.color ??
      _textPrimary.withValues(alpha: 0.75);
  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _errorColor => Theme.of(context).colorScheme.error;

  @override
  void initState() {
    super.initState();
    sftpShowHiddenSetting.addListener(_onShowHiddenChanged);
    _initSftp();
  }

  Future<void> _initSftp() async {
    try {
      final session = widget.session;
      final sftp = SftpService.resolving(() => session.sftpClient);
      await _loadPrefs();
      if (!mounted) return;
      setState(() => _sftp = sftp);
      await _initAndLoad();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = resolveSftpError(e, t);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPrefs() async {
    final field = await sftpSortFieldSetting.load();
    final descending = await sftpSortDescendingSetting.load();
    if (!mounted) return;
    setState(() {
      _sortField = field;
      _sortDescending = descending;
    });
  }

  Future<void> _toggleShowHidden() =>
      sftpShowHiddenSetting.set(!sftpShowHiddenSetting.value);

  /// The eye button and the switch in Settings are one setting; either way
  /// round, the listing is reloaded with or without the dotfiles.
  void _onShowHiddenChanged() {
    if (!mounted) return;
    setState(() => _showHidden = sftpShowHiddenSetting.value);
    unawaited(_loadDirectory());
  }

  Future<void> _setSort(SftpSortField field, bool descending) async {
    setState(() {
      _sortField = field;
      _sortDescending = descending;
    });
    await sftpSortFieldSetting.set(field);
    await sftpSortDescendingSetting.set(descending);
    await _loadDirectory();
  }

  @override
  void dispose() {
    _doubleClickTimer?.cancel();
    _listScroll.dispose();
    _keysFocus.dispose();
    sftpShowHiddenSetting.removeListener(_onShowHiddenChanged);
    for (final opener in _fileMenuOpeners.values) {
      opener.dispose();
    }
    unawaited(_sftp?.close());
    super.dispose();
  }

  /// Uses SFTP-native absolute path resolution, which works cross-platform -
  /// unlike the exec-channel `pwd`, which returns OS-native paths on Windows.
  Future<void> _initAndLoad() async {
    final sftp = _sftp;
    if (sftp == null) return;
    try {
      await sftp.init();
      try {
        _currentPath = await sftp.sftp.absolute('.');
      } catch (_) {
        _currentPath = '/';
      }
      final terminal = await widget.terminalDirectory?.call();
      if (terminal != null && await sftp.exists(terminal)) {
        _currentPath = terminal;
      }
      _followedDirectory = terminal;
      await _loadDirectory();
    } catch (e) {
      if (mounted) {
        final t = Translations.of(context);
        setState(() {
          _error = resolveSftpError(e, t);
          _isLoading = false;
        });
      }
    }
  }

  /// Goes to the terminal's directory if the shell has moved since the
  /// browser last went there, and leaves wherever the user browsed to if not.
  Future<void> followTerminal() async {
    if (_sftp == null || _selectionMode) return;
    final terminal = await widget.terminalDirectory?.call();
    if (!mounted || terminal == null || terminal == _followedDirectory) return;
    _followedDirectory = terminal;
    if (terminal == _currentPath) return;
    _history.add(_currentPath);
    _currentPath = terminal;
    await _loadDirectory();
  }

  int _compareItems(SftpName a, SftpName b) {
    if (a.filename == '..') return -1;
    if (b.filename == '..') return 1;
    final aDir = a.attr.isDirectory;
    final bDir = b.attr.isDirectory;
    if (aDir && !bDir) return -1;
    if (!aDir && bDir) return 1;

    int cmp;
    switch (_sortField) {
      case SftpSortField.name:
        cmp = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      case SftpSortField.size:
        cmp = (a.attr.size ?? 0).compareTo(b.attr.size ?? 0);
      case SftpSortField.modified:
        cmp = (a.attr.modifyTime ?? 0).compareTo(b.attr.modifyTime ?? 0);
    }
    return _sortDescending ? -cmp : cmp;
  }

  /// Clears the sniffed-text cache on every load, since a file may have been
  /// rewritten since it was last sniffed.
  ///
  /// Claims a new [_loadGeneration] before awaiting the listing, so if
  /// another call to this method starts and claims a later generation before
  /// this one's request resolves, this one notices on the way back - in
  /// success or in failure - and drops its result instead of overwriting
  /// whatever the newer, now-current load already put up. Without it, a
  /// navigation whose listing takes longer than the one after it could win
  /// the race and leave the list showing one directory while the path bar
  /// already points at another.
  Future<void> _loadDirectory({bool showSpinner = true}) async {
    if (!mounted || _sftp == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      if (showSpinner && _items.isEmpty) _isLoading = true;
      _isRefreshing = true;
      _error = '';
    });
    try {
      final items = await _sftp!.listDirectory(_currentPath);
      if (!mounted || generation != _loadGeneration) return;
      items.sort(_compareItems);
      _textProbes.clear();

      setState(() {
        _items = items.where((i) {
          if (i.filename == '.') return false;
          if (!_showHidden &&
              i.filename != '..' &&
              i.filename.startsWith('.')) {
            return false;
          }
          return true;
        }).toList();
        _isLoading = false;
        _isRefreshing = false;
        _selected.clear();
        _lastClicked = null;
        if (!_items.any((i) => i.filename == _cursor)) _cursor = null;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      final fallback = _history.isNotEmpty ? _history.removeLast() : null;
      if (fallback != null) {
        _currentPath = fallback;
      }
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      AppNotifications.error(
        context,
        resolveSftpError(e, Translations.of(context)),
      );
      if (fallback != null) await _loadDirectory();
    }
  }

  String _joinPath(String name) => joinRemotePath(_currentPath, name);

  void _navigateToSegment(int index) {
    if (_selectionMode) return;
    final target = remoteSegmentPath(_currentPath, index);
    if (target == _currentPath) return;
    _history.add(_currentPath);
    _currentPath = target;
    _loadDirectory();
  }

  void _navigateToRoot() {
    if (_selectionMode) return;
    final target = remoteRootPath(_currentPath);
    if (target == _currentPath) return;
    _history.add(_currentPath);
    _currentPath = target;
    _loadDirectory();
  }

  /// A symlink that fails to resolve is treated as a broken link, which
  /// falls through to being opened as a file.
  Future<void> _navigateTo(SftpName item) async {
    if (item.filename == '..') {
      _goUp();
      return;
    }
    var isDir = item.attr.isDirectory;
    if (!isDir && item.attr.isSymbolicLink && _sftp != null) {
      try {
        final resolved = await _sftp!.stat(
          _joinPath(item.filename),
          followLink: true,
        );
        isDir = resolved.isDirectory;
      } catch (_) {}
    }
    if (!isDir) {
      unawaited(_openFile(item));
      return;
    }
    _history.add(_currentPath);
    _currentPath = _joinPath(item.filename);
    unawaited(_loadDirectory());
  }

  void _goUp() {
    _history.add(_currentPath);
    _currentPath = sftpParentPath(_currentPath);
    unawaited(_loadDirectory());
  }

  bool get canGoBackHistory => _history.isNotEmpty;

  void goBackHistory() {
    if (_history.isNotEmpty) {
      _currentPath = _history.removeLast();
      unawaited(_loadDirectory());
    }
  }

  void _toggleSelected(String filename) {
    setState(() {
      if (_selected.contains(filename)) {
        _selected.remove(filename);
      } else {
        _selected.add(filename);
      }
    });
  }

  /// Selects every row, or - when every row already is - clears the
  /// selection, so the same button undoes itself.
  void _selectAll() {
    final all = _items
        .where((i) => i.filename != '..')
        .map((i) => i.filename)
        .toSet();
    setState(() {
      if (_selected.containsAll(all)) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all);
      }
    });
  }

  void _clearSelection() => setState(_selected.clear);

  /// The row a Shift-click or Shift-arrow extends a selection from.
  String? _lastClicked;

  /// The row the keyboard is on, on a desktop: where the arrows move from,
  /// what Enter opens and Space toggles. Usually the one selected row, but
  /// Ctrl (Cmd) with the arrows walks it past a selection without touching
  /// it.
  String? _cursor;

  /// The row a click just landed on, while a second click would still make
  /// it a double click. A timer rather than two timestamps, so the first
  /// click acts at once instead of waiting to learn whether it is half of a
  /// pair.
  String? _clickedOnce;
  Timer? _doubleClickTimer;

  final _listScroll = ScrollController();

  /// Takes the keyboard on a desktop: the browser answers the keys a file
  /// manager does.
  final _keysFocus = FocusNode(debugLabel: 'sftpBrowserKeys');

  /// Makes the rows between [from] and [to] the selection, both included.
  void _selectRange(String from, String to) {
    final names = _items.map((i) => i.filename).toList();
    final a = names.indexOf(from);
    final b = names.indexOf(to);
    if (a < 0 || b < 0) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(names.sublist(math.min(a, b), math.max(a, b) + 1))
        ..remove('..');
    });
  }

  /// A click on a desktop row, as a file manager takes it: it selects the
  /// row, Ctrl (Cmd) adds or removes it, Shift takes in everything from the
  /// row the selection started at, and a second click in time opens it.
  void _onDesktopClick(SftpName item) {
    final name = item.filename;
    if (rangeModifierPressed) {
      final from = _lastClicked ?? _cursor ?? name;
      _lastClicked = from;
      _cursor = name;
      _selectRange(from, name);
      return;
    }
    if (selectionModifierPressed) {
      _lastClicked = name;
      _cursor = name;
      if (name != '..') _toggleSelected(name);
      return;
    }
    if (_clickedOnce == name) {
      _doubleClickTimer?.cancel();
      _clickedOnce = null;
      unawaited(_navigateTo(item));
      return;
    }
    _doubleClickTimer?.cancel();
    _clickedOnce = name;
    _doubleClickTimer = Timer(kDoubleTapTimeout, () => _clickedOnce = null);
    _selectOnly(name);
  }

  /// Puts the cursor on [name] and makes it the whole selection; `..` takes
  /// the cursor and leaves nothing selected, there being nothing to do to
  /// it but open it.
  void _selectOnly(String name) {
    setState(() {
      _cursor = name;
      _lastClicked = name;
      _selected.clear();
      if (name != '..') _selected.add(name);
    });
  }

  /// Moves the cursor [step] rows. Plain, the row it lands on becomes the
  /// selection; with [extend] (Shift) the selection grows or shrinks from
  /// where it started; with [keep] (Ctrl, Cmd) only the cursor moves.
  void _moveCursor(int step, {required bool extend, required bool keep}) {
    if (_items.isEmpty) return;
    final names = _items.map((i) => i.filename).toList();
    final at = _cursor == null ? -1 : names.indexOf(_cursor!);
    final index = at < 0
        ? (step > 0 ? 0 : names.length - 1)
        : (at + step).clamp(0, names.length - 1);
    final name = names[index];
    if (extend) {
      final from = _lastClicked ?? (at < 0 ? name : names[at]);
      _lastClicked = from;
      _cursor = name;
      _selectRange(from, name);
    } else if (keep) {
      setState(() => _cursor = name);
    } else {
      _selectOnly(name);
    }
    _revealRow(index);
  }

  /// Scrolls just far enough that row [index] is on screen. The desktop's
  /// rows are all [kSftpRowHeight] tall, so where one is needs no measuring.
  void _revealRow(int index) {
    if (!_listScroll.hasClients) return;
    final position = _listScroll.position;
    final top = index * kSftpRowHeight;
    final bottom = top + kSftpRowHeight;
    if (top < position.pixels) {
      _listScroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _listScroll.jumpTo(bottom - position.viewportDimension);
    }
  }

  /// How many rows Page Up and Page Down move by: a screenful less one, so
  /// the row that was at the edge stays in view.
  int get _pageRows {
    if (!_listScroll.hasClients) return 10;
    final rows = _listScroll.position.viewportDimension ~/ kSftpRowHeight;
    return math.max(rows - 1, 1);
  }

  /// A right click: the row's own menu, opened where its `⋮` would open it -
  /// or, over a selection, what can be done to all of it.
  ///
  /// A row outside the selection becomes the selection first, so the menu is
  /// never about something other than what was clicked.
  void _onRowSecondaryTap(SftpName item, Offset globalPosition) {
    final t = Translations.of(context);
    _keysFocus.requestFocus();
    if (!_selected.contains(item.filename)) _selectOnly(item.filename);
    if (_selectionMode) {
      unawaited(
        showAppContextMenu(
          context,
          globalPosition: globalPosition,
          entries: [
            ContextMenuEntry(
              label: t.sftp.download,
              icon: PhosphorIconsRegular.downloadSimple,
              shortcut: AppCommands.describeActivator(SftpShortcuts.download),
              onSelected: () => unawaited(_downloadSelected()),
            ),
            if (_copyAvailable)
              ContextMenuEntry(
                label: t.sftp.copyTo,
                icon: PhosphorIconsRegular.folders,
                shortcut: AppCommands.describeActivator(SftpShortcuts.copyTo),
                onSelected: () => unawaited(_transferSelected(move: false)),
              ),
            ContextMenuEntry(
              label: t.sftp.moveTo,
              icon: PhosphorIconsRegular.arrowSquareRight,
              shortcut: AppCommands.describeActivator(SftpShortcuts.moveTo),
              onSelected: () => unawaited(_transferSelected(move: true)),
            ),
            null,
            ContextMenuEntry(
              label: t.common.delete,
              icon: PhosphorIconsRegular.trash,
              shortcut: AppCommands.describeActivator(SftpShortcuts.delete),
              destructive: true,
              onSelected: () => unawaited(_deleteSelected()),
            ),
          ],
        ),
      );
      return;
    }
    _menuOpenerFor(_joinPath(item.filename)).value = Object();
  }

  /// The browser's menu in the title bar: everything its keys do, each with
  /// its key, greyed out while there is nothing selected for it to act on.
  List<AppMenu> menus(Translations t) {
    final ready = _sftp != null;
    final some = ready && _selected.isNotEmpty;
    final one = ready && _selected.length == 1;
    return [
      AppMenu(t.window.menuFiles, [
        [
          AppMenuItem(
            label: t.sftp.newFolder,
            icon: PhosphorIconsRegular.folderPlus,
            activator: SftpShortcuts.newFolder,
            enabled: ready,
            onSelected: () => unawaited(_createFolder()),
          ),
          AppMenuItem(
            label: t.sftp.newFile,
            icon: PhosphorIconsRegular.filePlus,
            activator: SftpShortcuts.newFile,
            enabled: ready,
            onSelected: () => unawaited(_createFile()),
          ),
          AppMenuItem(
            label: t.sftp.uploadAction,
            icon: PhosphorIconsRegular.uploadSimple,
            enabled: ready,
            onSelected: () => unawaited(_uploadFile()),
          ),
        ],
        [
          AppMenuItem(
            label: t.common.rename,
            icon: PhosphorIconsRegular.pencilSimple,
            activator: SftpShortcuts.rename,
            enabled: one,
            onSelected: _renameSelected,
          ),
          AppMenuItem(
            label: t.sftp.download,
            icon: PhosphorIconsRegular.downloadSimple,
            activator: SftpShortcuts.download,
            enabled: some,
            onSelected: () => unawaited(_downloadSelected()),
          ),
          AppMenuItem(
            label: t.sftp.copyTo,
            icon: PhosphorIconsRegular.folders,
            activator: SftpShortcuts.copyTo,
            enabled: some && _copyAvailable,
            onSelected: () => unawaited(_transferSelected(move: false)),
          ),
          AppMenuItem(
            label: t.sftp.moveTo,
            icon: PhosphorIconsRegular.arrowSquareRight,
            activator: SftpShortcuts.moveTo,
            enabled: some,
            onSelected: () => unawaited(_transferSelected(move: true)),
          ),
          AppMenuItem(
            label: t.common.delete,
            icon: PhosphorIconsRegular.trash,
            activator: SftpShortcuts.delete,
            enabled: some,
            onSelected: () => unawaited(_deleteSelected()),
          ),
        ],
        [
          AppMenuItem(
            label: t.sftp.selectAll,
            icon: PhosphorIconsRegular.checks,
            activator: SftpShortcuts.selectAll,
            enabled: ready,
            onSelected: _selectAll,
          ),
        ],
        [
          AppMenuItem(
            label: t.sftp.parentFolder,
            icon: PhosphorIconsRegular.arrowUp,
            activator: SftpShortcuts.parentFolder,
            enabled: ready,
            onSelected: _goUp,
          ),
          AppMenuItem(
            label: t.sftp.back,
            icon: PhosphorIconsRegular.arrowLeft,
            activator: SftpShortcuts.back,
            enabled: canGoBackHistory,
            onSelected: goBackHistory,
          ),
          AppMenuItem(
            label: t.common.refresh,
            icon: PhosphorIconsRegular.arrowClockwise,
            activator: SftpShortcuts.refresh,
            enabled: ready,
            onSelected: () => unawaited(_loadDirectory(showSpinner: false)),
          ),
          AppMenuItem(
            label: t.sftp.showHidden,
            checked: _showHidden,
            activator: SftpShortcuts.toggleHidden,
            onSelected: () => unawaited(_toggleShowHidden()),
          ),
        ],
      ]),
    ];
  }

  void _renameSelected() {
    if (_selected.length != 1) return;
    final item = _items.where((i) => i.filename == _selected.first);
    if (item.isNotEmpty) unawaited(_renameItem(item.first));
  }

  /// The keys a file manager answers. Arrows, Page Up and Down, Home and
  /// End move the cursor and repeat while held; Shift extends the selection
  /// with them and Ctrl (Cmd) moves without selecting. Enter opens the row
  /// the cursor is on, Space adds it to the selection or takes it out. The
  /// rest - new folder, hidden files, rename, download and so on - are
  /// [SftpShortcuts], the list the menu and the tooltips print them from.
  KeyEventResult _onBrowserKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final primary = isMacOSPlatform
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final key = event.logicalKey;
    final step = switch (key) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.pageDown => _pageRows,
      LogicalKeyboardKey.pageUp => -_pageRows,
      LogicalKeyboardKey.end => _items.length,
      LogicalKeyboardKey.home => -_items.length,
      _ => null,
    };
    if (step != null && !keyboard.isAltPressed) {
      _moveCursor(step, extend: keyboard.isShiftPressed, keep: primary);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    bool pressed(SingleActivator activator) =>
        activator.accepts(event, keyboard);
    if (pressed(SftpShortcuts.back)) {
      goBackHistory();
      return KeyEventResult.handled;
    }
    if (pressed(SftpShortcuts.newFolder)) {
      unawaited(_createFolder());
      return KeyEventResult.handled;
    }
    if (pressed(SftpShortcuts.newFile)) {
      unawaited(_createFile());
      return KeyEventResult.handled;
    }
    if (pressed(SftpShortcuts.toggleHidden)) {
      unawaited(_toggleShowHidden());
      return KeyEventResult.handled;
    }
    if (pressed(SftpShortcuts.download)) {
      if (_selected.isNotEmpty) unawaited(_downloadSelected());
      return KeyEventResult.handled;
    }
    if (pressed(SftpShortcuts.moveTo)) {
      if (_selected.isNotEmpty) unawaited(_transferSelected(move: true));
      return KeyEventResult.handled;
    }
    if (pressed(SftpShortcuts.copyTo)) {
      if (_selected.isNotEmpty && _copyAvailable) {
        unawaited(_transferSelected(move: false));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final item = _items.where((i) => i.filename == _cursor).firstOrNull;
      if (item == null) return KeyEventResult.ignored;
      unawaited(_navigateTo(item));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      final cursor = _cursor;
      if (cursor == null || cursor == '..') return KeyEventResult.ignored;
      _lastClicked = cursor;
      _toggleSelected(cursor);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _selected.isNotEmpty) {
      _clearSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace && !primary) {
      final up = _items.where((i) => i.filename == '..').firstOrNull;
      if (up != null) _navigateTo(up);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f5) {
      unawaited(_loadDirectory(showSpinner: false));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete && _selected.isNotEmpty) {
      unawaited(_deleteSelected());
      return KeyEventResult.handled;
    }
    if (primary && key == LogicalKeyboardKey.keyA) {
      _selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2 && _selected.length == 1) {
      _renameSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    await _uploadLocalFiles([
      for (final file in result)
        if (file.path case final path?)
          (name: file.name, path: path, size: await file.length()),
    ]);
  }

  /// Files dropped on the browser from the desktop's file manager: uploaded
  /// into the folder on screen, as the + button's picker would. Folders are
  /// left out - a dropped tree is a sync, not an upload.
  Future<void> _uploadDropped(List<String> paths) async {
    final files = <_LocalFile>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      files.add((
        name: path.split(Platform.pathSeparator).last,
        path: path,
        size: await file.length(),
      ));
    }
    await _uploadLocalFiles(files);
  }

  /// Overwrite prompts have to come before the progress dialog, or a modal
  /// would be asking a question from behind another modal.
  Future<void> _uploadLocalFiles(List<_LocalFile> files) async {
    if (files.isEmpty || !mounted) return;
    final t = Translations.of(context);
    final planned = <_LocalFile>[];
    for (final file in files) {
      final remotePath = _joinPath(file.name);
      if (_sftp != null && await _sftp!.exists(remotePath)) {
        if (!mounted) return;
        if (await _confirmOverwrite(file.name) != true) continue;
      }
      planned.add(file);
    }
    if (planned.isEmpty || !mounted) return;

    final session = TransferSession(
      kind: TransferKind.upload,
      initialLabel: planned.first.name,
    )..show(context);

    var knownTotal = 0;
    for (final file in planned) {
      knownTotal += file.size ?? 0;
    }
    var bytesBefore = 0;
    var uploadedAny = false;
    try {
      for (var i = 0; i < planned.length; i++) {
        session.cancel.throwIfCancelled();
        final file = planned[i];
        var sent = 0;
        await _sftp?.uploadFile(
          file.path,
          _joinPath(file.name),
          cancel: session.cancel,
          onProgress: (uploaded, _) {
            sent = uploaded;
            final overall = bytesBefore + uploaded;
            session.update(
              TransferProgress(
                label: file.name,
                itemIndex: i + 1,
                itemCount: planned.length,
                bytes: overall,
                totalBytes: knownTotal > 0 ? knownTotal : null,
                fraction: knownTotal > 0
                    ? (overall / knownTotal).clamp(0.0, 1.0)
                    : null,
              ),
            );
          },
        );
        bytesBefore += sent;
        uploadedAny = true;
      }
      session.close();
    } catch (e) {
      session.close();
      if (mounted) {
        if (session.isCancelled || e is TransferCancelled) {
          AppNotifications.info(context, t.sftp.uploadCancelled);
        } else {
          AppNotifications.error(context, resolveSftpError(e, t));
        }
      }
    }
    if (uploadedAny) await _loadDirectory();
  }

  Future<bool> _confirmOverwrite(String filename) {
    final t = Translations.of(context);
    return showConfirmDialog(
      context,
      title: t.sftp.overwriteTitle,
      message: t.sftp.overwriteConfirm(filename: filename),
      confirmLabel: t.sftp.overwrite,
      destructive: true,
    );
  }

  /// Says where the download landed and offers to open it - a finished
  /// transfer should never end in silence.
  void _announceSaved(SavedDownload saved) {
    if (!mounted) return;
    final t = Translations.of(context);
    final message = saved.fileCount > 1
        ? t.sftp.savedFilesToDownloads(
            count: saved.fileCount,
            folder: saved.fileName,
          )
        : t.sftp.savedToDownloads(name: saved.fileName);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? (box.localToGlobal(Offset.zero) & box.size)
        : null;
    AppNotifications.success(
      context,
      message,
      actionLabel: saved.uri == null
          ? null
          : platformHas(PlatformFeature.revealInFileManager)
          ? t.contextMenu.showInFolder
          : (isIOSPlatform ? t.sftp.shareDownload : t.sftp.openDownload),
      onAction: saved.uri == null
          ? null
          : platformHas(PlatformFeature.revealInFileManager)
          ? () => DownloadService.revealSavedDownload(saved)
          : () async {
              try {
                await DownloadService.openSavedDownload(
                  saved,
                  sharePositionOrigin: origin,
                );
              } catch (_) {
                if (mounted) {
                  AppNotifications.info(
                    context,
                    isIOSPlatform ? t.sftp.couldNotShare : t.sftp.noAppToOpen,
                  );
                }
              }
            },
    );
  }

  /// Downloads one entry - a file straight through, a directory packed on the
  /// server when it can pack, walked and copied file by file when it cannot.
  Future<void> _downloadFile(SftpName item) async {
    final sftp = _sftp;
    if (sftp == null) return;

    await _runDownload(
      label: item.filename,
      run: (session) => item.attr.isDirectory
          ? DownloadService.downloadSftpDirectory(
              sftp: sftp,
              remotePath: _joinPath(item.filename),
              folderName: item.filename,
              cancel: session.cancel,
              onProgress: session.update,
            )
          : DownloadService.downloadSftpFile(
              sftp: sftp,
              remotePath: _joinPath(item.filename),
              fileName: item.filename,
              cancel: session.cancel,
              onProgress: session.update,
            ),
    );
  }

  Future<void> _downloadSelected() async {
    final sftp = _sftp;
    final items = _items.where((i) => _selected.contains(i.filename)).toList();
    if (sftp == null || items.isEmpty) return;
    _clearSelection();
    final t = Translations.of(context);

    await _runDownload(
      label: items.first.filename,
      run: (session) => DownloadService.downloadSftpSelection(
        sftp: sftp,
        parentPath: _currentPath,
        entries: items
            .map(
              (item) => SftpEntryRef(
                name: item.filename,
                isDirectory: item.attr.isDirectory,
                size: item.attr.size,
              ),
            )
            .toList(),
        multiFileLabel: t.sftp.downloadsFolder,
        cancel: session.cancel,
        onProgress: session.update,
      ),
    );
  }

  /// The one place a download is shown and torn down: the dialog goes up
  /// before the first byte, comes down on every exit path, and a cancelled
  /// transfer is reported as cancelled rather than as a failure.
  Future<void> _runDownload({
    required String label,
    required Future<SavedDownload?> Function(TransferSession session) run,
  }) async {
    final t = Translations.of(context);
    final session = TransferSession(
      kind: TransferKind.download,
      initialLabel: label,
    )..show(context);

    try {
      final saved = await run(session);
      session.close();
      if (!mounted || session.isCancelled || saved == null) return;
      _announceSaved(saved);
    } catch (e) {
      session.close();
      if (!mounted) return;
      if (session.isCancelled || e is TransferCancelled) {
        AppNotifications.info(context, t.sftp.downloadCancelled);
      } else {
        AppNotifications.error(context, resolveSftpError(e, t));
      }
    }
  }

  /// A partly deleted directory still changed on disk, so the listing is
  /// refreshed either way.
  Future<void> _deleteItem(SftpName item) async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.sftp.deleteTitle,
      message: t.sftp.deleteConfirm(filename: item.filename),
      confirmLabel: t.common.delete,
      destructive: true,
    );
    if (!confirmed || _sftp == null) return;

    Object? failure;
    try {
      await _sftp!.deletePath(
        _joinPath(item.filename),
        isDirectory: item.attr.isDirectory,
      );
    } catch (e) {
      failure = e;
    }
    await _loadDirectory(showSpinner: false);
    if (mounted && failure != null) {
      AppNotifications.error(context, resolveSftpError(failure, t));
    }
  }

  /// One failure should not strand the rest: every item is attempted and the
  /// outcome is reported together.
  Future<void> _deleteSelected() async {
    final t = Translations.of(context);
    final items = _items.where((i) => _selected.contains(i.filename)).toList();
    if (_sftp == null || items.isEmpty) return;
    final confirmed = await showConfirmDialog(
      context,
      title: t.sftp.deleteSelectedTitle(count: items.length),
      message: t.sftp.deleteSelectedConfirm(count: items.length),
      confirmLabel: t.common.delete,
      destructive: true,
    );
    if (!confirmed) return;
    _clearSelection();

    final failures = <String, Object>{};
    for (final item in items) {
      try {
        await _sftp!.deletePath(
          _joinPath(item.filename),
          isDirectory: item.attr.isDirectory,
        );
      } catch (e) {
        failures[item.filename] = e;
      }
    }
    await _loadDirectory(showSpinner: false);
    if (!mounted || failures.isEmpty) return;

    if (failures.length == 1) {
      final entry = failures.entries.single;
      AppNotifications.error(
        context,
        '${entry.key}: ${resolveSftpError(entry.value, t)}',
      );
    } else {
      AppNotifications.error(
        context,
        t.sftp.deleteFailedCount(
          count: failures.length,
          error: resolveSftpError(failures.values.first, t),
        ),
      );
    }
  }

  /// The server renames straight over whatever is already called that, so
  /// the overwrite question has to be asked here - the same one an upload
  /// asks.
  Future<void> _renameItem(SftpName item) async {
    final t = Translations.of(context);
    final newName = await showTextInputDialog(
      context,
      title: t.common.rename,
      confirmLabel: t.common.rename,
      initialValue: item.filename,
    );
    if (newName == null || newName.isEmpty || newName == item.filename) return;

    final target = _joinPath(newName);
    if (_sftp != null && await _sftp!.exists(target)) {
      if (!mounted) return;
      if (!await _confirmOverwrite(newName)) return;
    }
    if (!mounted) return;

    try {
      await _sftp?.rename(_joinPath(item.filename), target);
      await _loadDirectory();
    } catch (e) {
      if (mounted) {
        AppNotifications.error(context, resolveSftpError(e, t));
      }
    }
  }

  List<RemoteEntry> _entriesOf(List<SftpName> items) => [
    for (final item in items)
      RemoteEntry(
        item.filename,
        isDirectory: item.attr.isDirectory && !item.attr.isSymbolicLink,
      ),
  ];

  Future<void> _transferSelected({required bool move}) {
    final items = _items.where((i) => _selected.contains(i.filename)).toList();
    return _transferTo(items, move: move);
  }

  /// Copy to / move to: pick a folder, settle clashes once for the lot, and
  /// have the server do the work. A copy into its own folder can only mean
  /// a second one beside it, so conflicts are skipped and everything keeps
  /// both.
  Future<void> _transferTo(List<SftpName> items, {required bool move}) async {
    final sftp = _sftp;
    if (sftp == null || items.isEmpty || _transferring) return;
    final t = Translations.of(context);
    final sourceDirectory = _currentPath;
    final sources = [for (final item in items) _joinPath(item.filename)];
    final single = items.length == 1 ? items.single.filename : null;
    final machine = widget.session.profile.id;

    final destination = await showSftpFolderPicker(
      context: context,
      sftp: sftp,
      title: switch ((move, single)) {
        (true, final String name) => t.sftp.moveNameTo(name: name),
        (true, null) => t.sftp.moveItemsTo(count: items.length),
        (false, final String name) => t.sftp.copyNameTo(name: name),
        (false, null) => t.sftp.copyItemsTo(count: items.length),
      },
      actionLabel: move ? t.sftp.moveHere : t.sftp.copyHere,
      startPath: sourceDirectory,
      canChoose: (folder) => canTransferInto(
        destination: folder,
        sourceDirectory: sourceDirectory,
        sources: sources,
        move: move,
      ),
      canEnter: (folder) => !sources.any((s) => isSameOrInside(folder, s)),
      recent: _recentDestinations[machine] ?? const [],
      showHidden: _showHidden,
    );
    if (destination == null || !mounted) return;
    _clearSelection();
    final recent = _recentDestinations.putIfAbsent(machine, () => [])
      ..removeWhere((r) => sameSftpPath(r, destination))
      ..insert(0, destination);
    if (recent.length > 4) recent.removeRange(4, recent.length);

    final entries = _entriesOf(items);
    final existing = await _namesIn(destination);
    if (existing == null || !mounted) return;

    var choice = ConflictChoice.keepBoth;
    if (!sameSftpPath(destination, sourceDirectory)) {
      final conflicts = transferConflicts(
        entries,
        existing,
        destination: destination,
      );
      if (conflicts.isNotEmpty) {
        final picked = await askTransferConflict(
          context,
          conflicts,
          total: entries.length,
          folder: destination,
        );
        if (picked == null || !mounted) return;
        choice = picked;
      }
    }
    await _runTransfers(
      planTransfers(
        sourceDirectory: sourceDirectory,
        entries: entries,
        destination: destination,
        existing: existing,
        choice: choice,
      ),
      move: move,
    );
  }

  Future<void> _duplicate(SftpName item) async {
    if (_sftp == null || _transferring) return;
    final existing = await _namesIn(_currentPath);
    if (existing == null || !mounted) return;
    await _runTransfers(
      planTransfers(
        sourceDirectory: _currentPath,
        entries: _entriesOf([item]),
        destination: _currentPath,
        existing: existing,
        choice: ConflictChoice.keepBoth,
      ),
      move: false,
    );
  }

  /// Read fresh rather than off [_items], which leaves out dotfiles when they
  /// are hidden - and a name picked to keep both must clash with none.
  Future<Set<String>?> _namesIn(String folder) async {
    try {
      final entries = await _sftp!.listDirectory(folder);
      return {for (final e in entries) e.filename};
    } catch (e) {
      if (mounted) {
        AppNotifications.error(
          context,
          resolveSftpError(e, Translations.of(context)),
        );
      }
      return null;
    }
  }

  /// No cancel: stopping `cp` halfway leaves half a folder, and closing the
  /// channel does not reliably stop it anyway.
  ///
  /// One failure does not strand the rest, as with delete - except when the
  /// account has no shell to run `cp`/`mv` on, since nothing after that can
  /// go either.
  Future<void> _runTransfers(TransferPlan plan, {required bool move}) async {
    final t = Translations.of(context);
    final sftp = _sftp;
    if (sftp == null) return;
    if (plan.transfers.isEmpty) {
      AppNotifications.info(context, t.sftp.nothingTransferred);
      return;
    }
    setState(() => _busyLabel = move ? t.sftp.moving : t.sftp.copying);

    final failures = <String, Object>{};
    for (final transfer in plan.transfers) {
      try {
        if (transfer.replaceExisting) await sftp.clearPath(transfer.to);
        if (move) {
          await sftp.moveEntry(transfer.from, transfer.to);
        } else {
          await sftp.copyEntry(transfer.from, transfer.to);
        }
      } catch (e) {
        failures[transfer.entry.name] = e;
        if (sftp.canRunCommands == false) break;
      }
    }
    if (mounted) setState(() => _busyLabel = null);
    await _loadDirectory(showSpinner: false);
    if (!mounted) return;

    if (failures.isEmpty) {
      final done = plan.transfers.length;
      final name = plan.transfers.first.to.split('/').last;
      var message = switch ((move, done)) {
        (true, 1) => t.sftp.movedName(name: name),
        (true, _) => t.sftp.movedCount(count: done),
        (false, 1) => t.sftp.copiedName(name: name),
        (false, _) => t.sftp.copiedCount(count: done),
      };
      if (plan.skipped > 0) {
        message = '$message  ·  ${t.sftp.skippedCount(count: plan.skipped)}';
      }
      AppNotifications.success(context, message);
    } else if (failures.length == 1) {
      final entry = failures.entries.single;
      AppNotifications.error(
        context,
        '${entry.key}: ${resolveSftpError(entry.value, t)}',
      );
    } else {
      final error = resolveSftpError(failures.values.first, t);
      AppNotifications.error(
        context,
        move
            ? t.sftp.moveFailedCount(count: failures.length, error: error)
            : t.sftp.copyFailedCount(count: failures.length, error: error),
      );
    }
  }

  Future<void> _createFolder() async {
    final t = Translations.of(context);
    final name = await showTextInputDialog(
      context,
      title: t.sftp.newFolderTitle,
      confirmLabel: t.sftp.create,
      hintText: t.sftp.folderNameHint,
    );
    if (name == null || name.isEmpty || _sftp == null) return;
    try {
      await _sftp!.createDirectory(_joinPath(name));
      await _loadDirectory();
    } catch (e) {
      if (mounted) {
        AppNotifications.error(
          context,
          t.sftp.createFailed(error: resolveSftpError(e, t)),
        );
      }
    }
  }

  Future<void> _createFile() async {
    final t = Translations.of(context);
    final name = await showTextInputDialog(
      context,
      title: t.sftp.newFileTitle,
      confirmLabel: t.sftp.create,
      hintText: t.sftp.fileNameHint,
    );
    if (name == null || name.isEmpty || _sftp == null) return;
    try {
      await _sftp!.createEmptyFile(_joinPath(name));
      await _loadDirectory();
    } catch (e) {
      if (mounted) {
        AppNotifications.error(
          context,
          t.sftp.createFailed(error: resolveSftpError(e, t)),
        );
      }
    }
  }

  /// Reads the first few KB and decides from the bytes - not from the name -
  /// whether the file is text the editor can safely round-trip. Results are
  /// cached per directory listing.
  Future<TextProbe?> _probeText(SftpName item) async {
    final path = _joinPath(item.filename);
    final cached = _textProbes[path];
    if (cached != null) return cached;
    final sftp = _sftp;
    if (sftp == null) return null;

    setState(() => _probingPaths.add(path));
    try {
      const headSize = 8 * 1024;
      final head = await sftp.readFileHead(path, maxBytes: headSize);
      final probe = probeTextContent(
        head,
        truncated: item.attr.size != null && item.attr.size! > head.length,
      );
      _textProbes[path] = probe;
      return probe;
    } catch (e) {
      if (mounted) {
        AppNotifications.error(
          context,
          resolveSftpError(e, Translations.of(context)),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _probingPaths.remove(path));
    }
  }

  /// A pushed route carries no ambient theme with it, unlike a dialog or a
  /// sheet - the editor is still part of the session, so it is wrapped back
  /// into the session's colours by hand.
  void _openEditor(SftpName item) {
    pushAppWindow<void>(
      context,
      builder: (_) => TerminalSchemeTheme(
        child: SftpEditorScreen(
          session: widget.session,
          fileItem: item,
          path: _joinPath(item.filename),
          sftp: _sftp,
        ),
      ),
    );
  }

  /// When the file is not text, its actions menu still offers opening it,
  /// just not by default - this opens the same menu the row's own `⋮`
  /// button would.
  Future<void> _openFile(SftpName item) async {
    if (fileTypeOf(item.filename) == FileKind.image) {
      _openImage(item);
      return;
    }
    final probe = await _probeText(item);
    if (!mounted) return;
    if (probe == null) return;
    if (probe.isText) {
      _openEditor(item);
      return;
    }
    _menuOpenerFor(_joinPath(item.filename)).value = Object();
  }

  /// Whether the preview screen mutated anything is flagged on the way out
  /// rather than returned as a pop result: a route that has to report one
  /// needs `canPop: false`, which costs the predictive-back preview.
  /// Reloading once on return rather than on each delete keeps it to a
  /// single round trip.
  void _openImage(SftpName item) {
    if (_sftp == null) return;
    final siblings = _items
        .where(
          (i) => i.filename != '..' && fileTypeOf(i.filename) == FileKind.image,
        )
        .toList();
    var mutated = false;
    pushAppWindow<void>(
      context,
      builder: (_) => TerminalSchemeTheme(
        child: SftpImagePreviewScreen(
          sftp: _sftp!,
          path: _joinPath(item.filename),
          filename: item.filename,
          fileSize: item.attr.size,
          modifyTime: item.attr.modifyTime,
          directoryPath: _currentPath,
          siblingImages: siblings,
          onMutated: () => mutated = true,
        ),
      ),
    ).then((_) {
      if (mutated) _loadDirectory();
    });
  }

  /// What [SftpFileActionsMenu] reports back once a row's action is picked.
  void _handleFileAction(SftpFileAction action, SftpName item, String path) {
    final t = Translations.of(context);
    switch (action) {
      case SftpFileAction.openEditor:
        _openEditor(item);
      case SftpFileAction.preview:
        _openImage(item);
      case SftpFileAction.download:
        _downloadFile(item);
      case SftpFileAction.copyPath:
        copyToClipboard(
          context,
          sftpPathToDisplay(path),
          message: t.sftp.pathCopied,
        );
      case SftpFileAction.rename:
        _renameItem(item);
      case SftpFileAction.copyTo:
        _transferTo([item], move: false);
      case SftpFileAction.moveTo:
        _transferTo([item], move: true);
      case SftpFileAction.duplicate:
        _duplicate(item);
      case SftpFileAction.delete:
        _deleteItem(item);
    }
  }

  Future<void> _showSortMenu() async {
    final result = await showSftpSortSheet(
      context,
      field: _sortField,
      descending: _sortDescending,
    );
    if (result != null && mounted) await _setSort(result.$1, result.$2);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _background,
      child: Column(
        children: [
          _selectionMode
              ? SftpSelectionBar(
                  count: _selected.length,
                  copyAvailable: _copyAvailable,
                  onClear: _clearSelection,
                  onCopy: () => _transferSelected(move: false),
                  onMove: () => _transferSelected(move: true),
                  onDelete: _deleteSelected,
                  onSelectAll: _selectAll,
                  onDownload: _downloadSelected,
                )
              : SftpPathBar(
                  currentPath: _currentPath,
                  refreshing: _isRefreshing,
                  showHidden: _showHidden,
                  onNavigateToSegment: _navigateToSegment,
                  onNavigateToRoot: _navigateToRoot,
                  onPathSubmitted: _navigateToTypedPath,
                  onRefresh: () =>
                      unawaited(_loadDirectory(showSpinner: false)),
                  onSort: isDesktopPlatform ? null : _showSortMenu,
                  onToggleHidden: () => unawaited(_toggleShowHidden()),
                  onEditingChanged: (editing) =>
                      setState(() => _editingPath = editing),
                  trailing: _sftp != null ? _buildAddButton() : null,
                ),
          Divider(height: 1, color: _border),
          if (_busyLabel != null) _buildBusyStrip(_busyLabel!),
          Expanded(
            child: Stack(
              children: [
                _buildDesktopInput(_buildList()),
                if (_editingPath)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The "+" trigger, sitting in the path bar beside sort and hidden files
  /// rather than floating over the list - down there it covered the last row
  /// and the overflow button on it, since the list has no bottom padding.
  ///
  /// Still an [AppActionDropdown] rather than a button that opens a menu: it
  /// anchors its own menu to whatever tap lands on its `child`, and a real
  /// button's ink response would fight it for that gesture.
  Widget _buildAddButton() {
    final t = Translations.of(context);
    return AppActionDropdown<_AddAction>(
      width: 220,
      onSelected: (action) {
        switch (action) {
          case _AddAction.upload:
            _uploadFile();
          case _AddAction.newFolder:
            _createFolder();
          case _AddAction.newFile:
            _createFile();
        }
      },
      items: [
        DropdownItem(
          value: _AddAction.upload,
          intrinsicHeight: true,
          child: AppDropdownItem(
            icon: PhosphorIconsFill.uploadSimple,
            label: t.sftp.uploadAction,
          ),
        ),
        DropdownItem(
          value: _AddAction.newFolder,
          intrinsicHeight: true,
          child: AppDropdownItem(
            icon: PhosphorIconsFill.folderPlus,
            label: t.sftp.newFolder,
            trailing: ShortcutHint.of(SftpShortcuts.newFolder),
          ),
        ),
        DropdownItem(
          value: _AddAction.newFile,
          intrinsicHeight: true,
          child: AppDropdownItem(
            icon: PhosphorIconsFill.filePlus,
            label: t.sftp.newFile,
            trailing: ShortcutHint.of(SftpShortcuts.newFile),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(PhosphorIconsRegular.plus, color: _accent, size: 18),
      ),
    );
  }

  Widget _buildBusyStrip(String label) {
    return Container(
      color: _surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// What [SftpPathBar] reports back once a typed or pasted path is
  /// submitted - still in display form, trimmed.
  void _navigateToTypedPath(String value) {
    final path = displayPathToSftp(value);
    if (path.isNotEmpty) {
      _history.add(_currentPath);
      _currentPath = path;
    }
    _loadDirectory();
  }

  bool _dropHovering = false;

  /// On a desktop the list takes keys and dropped files. A phone gets the
  /// list as it was: no keys to take, nothing dragged in from outside.
  Widget _buildDesktopInput(Widget list) {
    if (!isDesktopPlatform) return list;
    return Focus(
      focusNode: _keysFocus,
      onKeyEvent: _onBrowserKey,
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dropHovering = true),
        onDragExited: (_) => setState(() => _dropHovering = false),
        onDragDone: (details) {
          setState(() => _dropHovering = false);
          unawaited(
            _uploadDropped([for (final file in details.files) file.path]),
          );
        },
        child: Stack(
          children: [
            list,
            if (_dropHovering)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey('sftpDropTarget'),
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.08),
                      border: Border.all(color: _accent, width: 1.5),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      Translations.of(context).sftp.dropToUpload(
                        folder: sftpPathToDisplay(_currentPath),
                      ),
                      style: TextStyle(
                        color: _accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Pulling the list down refreshes it on a phone only. A desktop has no
  /// pull - a wheel at the top of a list is just a wheel at the top - and
  /// refreshes on [SftpShortcuts.refresh], the path bar's button or the
  /// Files menu.
  Widget _buildList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_error, style: TextStyle(color: _errorColor)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = isDesktopPlatform
            ? SftpColumns.forWidth(constraints.maxWidth)
            : null;
        final list = ListView.builder(
          controller: _listScroll,
          padding: EdgeInsets.zero,
          physics: columns == null
              ? const AlwaysScrollableScrollPhysics()
              : null,
          itemExtent: columns == null ? null : kSftpRowHeight,
          itemCount: _items.length,
          itemBuilder: (context, index) =>
              _buildItem(_items[index], columns: columns),
        );
        return Column(
          children: [
            if (_isRefreshing)
              LinearProgressIndicator(
                minHeight: 2,
                color: _accent,
                backgroundColor: _surface.invisible,
              ),
            if (columns != null)
              SftpColumnHeader(
                columns: columns,
                field: _sortField,
                descending: _sortDescending,
                onSort: (field, descending) =>
                    unawaited(_setSort(field, descending)),
              ),
            Expanded(
              child: columns != null
                  ? list
                  : RefreshIndicator(
                      onRefresh: () => _loadDirectory(showSpinner: false),
                      child: list,
                    ),
            ),
          ],
        );
      },
    );
  }

  /// A phone opens a row on a tap and selects on a long press. A desktop
  /// selects on a click and opens on the second ([_onDesktopClick]), opens
  /// the row's menu on a right click, and lays the listing out as a table
  /// ([columns]) under a header that sorts it. Its rows carry no checkmark:
  /// the highlight says which are selected, and the `⋮` stays where it was.
  Widget _buildItem(SftpName item, {required SftpColumns? columns}) {
    final isUp = item.filename == '..';
    final path = _joinPath(item.filename);
    final desktop = isDesktopPlatform;
    final row = SftpFileRow(
      item: item,
      columns: columns,
      isCursor: desktop && _cursor == item.filename,
      path: path,
      isSelected: _selected.contains(item.filename),
      selectionMode: !desktop && _selectionMode,
      isProbing: _probingPaths.contains(path),
      probe: _textProbes[path],
      runProbe: () => _probeText(item),
      opener: _menuOpenerFor(path),
      copyAvailable: _copyAvailable,
      onTap: () {
        _keysFocus.requestFocus();
        if (desktop) {
          _onDesktopClick(item);
          return;
        }
        if (_selectionMode && !isUp) {
          _toggleSelected(item.filename);
          return;
        }
        _navigateTo(item);
      },
      onLongPress: () {
        if (isUp || desktop) return;
        _toggleSelected(item.filename);
      },
      onAction: (action) => _handleFileAction(action, item, path),
    );
    if (isUp || !desktop) return row;
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _onRowSecondaryTap(item, details.globalPosition),
      child: row,
    );
  }
}

/// A file on this machine on its way up: from the picker or dropped on the
/// browser.
typedef _LocalFile = ({String name, String path, int? size});
