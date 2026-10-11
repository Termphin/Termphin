import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/app/app_commands.dart';
import '../../services/sftp/sftp_remote_ops.dart';
import '../../services/sftp/sftp_service.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../../utils/sftp_error_handler.dart';
import '../../utils/sftp_path.dart';
import '../ui/app_notifications.dart';
import '../ui/app_sheet.dart';
import '../ui/sheet_handle.dart';
import '../ui/text_input_dialog.dart';
import 'sftp_shortcuts.dart';

/// Where a copy or move goes, picked by walking the server's folders. Returns
/// the chosen folder's SFTP path, or null.
///
/// Only folders are listed and nothing here acts on a file: it is a
/// destination picker, not a second browser.
Future<String?> showSftpFolderPicker({
  required BuildContext context,
  required SftpService sftp,
  required String title,
  required String actionLabel,
  required String startPath,
  required bool Function(String folder) canChoose,
  required bool Function(String folder) canEnter,
  List<String> recent = const [],
  bool showHidden = false,
}) {
  return showAppSheet<String>(
    context: context,
    handle: false,
    builder: (_) => SftpFolderPicker(
      sftp: sftp,
      title: title,
      actionLabel: actionLabel,
      startPath: startPath,
      canChoose: canChoose,
      canEnter: canEnter,
      recent: recent,
      showHidden: showHidden,
    ),
  );
}

class SftpFolderPicker extends StatefulWidget {
  const SftpFolderPicker({
    super.key,
    required this.sftp,
    required this.title,
    required this.actionLabel,
    required this.startPath,
    required this.canChoose,
    required this.canEnter,
    this.recent = const [],
    this.showHidden = false,
    this.onChoose,
  });

  final SftpService sftp;
  final String title;
  final String actionLabel;
  final String startPath;

  /// Whether the folder being shown may be the destination.
  final bool Function(String folder) canChoose;

  /// Whether a listed folder may be opened - a folder being moved cannot be
  /// a destination, and neither can anything inside it.
  final bool Function(String folder) canEnter;
  final List<String> recent;
  final bool showHidden;

  /// Makes this a page of its own rather than a sheet, handing the chosen
  /// folder here instead of popping with it - what a share uses, where the
  /// folder is the whole screen and nothing sits under it.
  final ValueChanged<String>? onChoose;

  @override
  State<SftpFolderPicker> createState() => _SftpFolderPickerState();
}

class _SftpFolderPickerState extends State<SftpFolderPicker> {
  late String _path = widget.startPath;
  List<SftpName> _folders = [];
  bool _loading = true;
  String _error = '';
  bool _editing = false;
  final _pathController = TextEditingController();

  /// Bumped by every call to [_load], so a listing that resolves after a
  /// newer one has already started can tell it is stale and drop its result.
  int _loadGeneration = 0;

  /// The row the keyboard is on, on a desktop - an index into [_rows] - or
  /// null while it is on none, when Enter means the folder being shown.
  int? _cursor;

  /// The row a click just landed on, while a second click would still open
  /// it; see `SftpBrowserViewState`, whose listing this one behaves like.
  int? _clickedOnce;
  Timer? _doubleClickTimer;

  final _keysFocus = FocusNode(debugLabel: 'sftpFolderPickerKeys');
  final _ownScroll = ScrollController();
  ScrollController? _listScroll;

  /// Height of a row on a desktop. Fixed, so the keyboard can scroll to a
  /// row that has not been built.
  static const double _desktopRowHeight = 30;

  @override
  void initState() {
    super.initState();
    _load(widget.startPath);
  }

  @override
  void dispose() {
    _doubleClickTimer?.cancel();
    _keysFocus.dispose();
    _ownScroll.dispose();
    _pathController.dispose();
    super.dispose();
  }

  /// What the list shows, in order: the way up, then the folders.
  List<({String name, String path, bool enabled, bool up})> get _rows => [
    if (!_atRoot)
      (name: '..', path: sftpParentPath(_path), enabled: true, up: true),
    for (final folder in _folders)
      (
        name: folder.filename,
        path: joinSftpPath(_path, folder.filename),
        enabled: widget.canEnter(joinSftpPath(_path, folder.filename)),
        up: false,
      ),
  ];

  bool get _canChooseHere =>
      !_loading && _error.isEmpty && widget.canChoose(_path);

  /// A desktop's click: the first puts the cursor on the row, the second in
  /// time opens it, as in the browser this was opened from.
  void _onDesktopClick(int index) {
    _keysFocus.requestFocus();
    final row = _rows[index];
    if (_clickedOnce == index) {
      _doubleClickTimer?.cancel();
      _clickedOnce = null;
      if (row.enabled) _load(row.path);
      return;
    }
    _doubleClickTimer?.cancel();
    _clickedOnce = index;
    _doubleClickTimer = Timer(kDoubleTapTimeout, () => _clickedOnce = null);
    setState(() => _cursor = index);
  }

  void _moveCursor(int step) {
    final count = _rows.length;
    if (count == 0) return;
    final at = _cursor;
    final index = at == null
        ? (step > 0 ? 0 : count - 1)
        : (at + step).clamp(0, count - 1);
    setState(() => _cursor = index);
    final scroll = _listScroll;
    if (scroll == null || !scroll.hasClients) return;
    final position = scroll.position;
    final top = index * _desktopRowHeight;
    final bottom = top + _desktopRowHeight;
    if (top < position.pixels) {
      scroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      scroll.jumpTo(bottom - position.viewportDimension);
    }
  }

  /// The picker's keys on a desktop, a file dialog's: the arrows walk the
  /// folders, Enter opens the one the cursor is on - or, on none, picks the
  /// folder being shown - Ctrl (Cmd) + Enter picks it from anywhere,
  /// Backspace goes up and F7 makes a folder. Esc is the dialog's own.
  /// While the path is being typed the keys are the field's.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _editing) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final step = switch (key) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.pageDown => 10,
      LogicalKeyboardKey.pageUp => -10,
      LogicalKeyboardKey.end => _rows.length,
      LogicalKeyboardKey.home => -_rows.length,
      _ => null,
    };
    if (step != null) {
      _moveCursor(step);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (SftpShortcuts.chooseHere.accepts(event, keyboard)) {
      if (_canChooseHere) _choose(_path);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final cursor = _cursor;
      if (cursor == null) {
        if (_canChooseHere) _choose(_path);
      } else if (cursor < _rows.length && _rows[cursor].enabled) {
        _load(_rows[cursor].path);
      }
      return KeyEventResult.handled;
    }
    if (SftpShortcuts.parentFolder.accepts(event, keyboard)) {
      if (!_atRoot) _load(sftpParentPath(_path));
      return KeyEventResult.handled;
    }
    if (SftpShortcuts.newFolder.accepts(event, keyboard)) {
      if (!_loading && _error.isEmpty) unawaited(_createFolder());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool get _atRoot => sftpParentPath(_path) == _path;

  /// A folder that cannot be opened leaves the last good listing up.
  ///
  /// Claims a new [_loadGeneration] before awaiting the listing, so if
  /// another call to this method starts and claims a later generation
  /// before this one's request resolves, this one notices on the way back -
  /// success or failure - and drops its result rather than overwriting
  /// [_path] and [_folders] with a slower, now-stale listing.
  Future<void> _load(String path) async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final entries = await widget.sftp.listDirectory(path);
      final folders =
          entries.where((e) {
            if (e.filename == '.' || e.filename == '..') return false;
            if (!widget.showHidden && e.filename.startsWith('.')) return false;
            return e.attr.isDirectory;
          }).toList()..sort(
            (a, b) =>
                a.filename.toLowerCase().compareTo(b.filename.toLowerCase()),
          );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _path = path;
        _folders = folders;
        _loading = false;
        _cursor = null;
        _clickedOnce = null;
      });
      final scroll = _listScroll;
      if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      final message = resolveSftpError(e, Translations.of(context));
      if (_folders.isNotEmpty || path != _path) {
        setState(() => _loading = false);
        AppNotifications.error(context, message);
      } else {
        setState(() {
          _loading = false;
          _error = message;
        });
      }
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
    if (name == null || name.isEmpty || !mounted) return;
    final path = joinSftpPath(_path, name);
    try {
      await widget.sftp.createDirectory(path);
      await _load(path);
    } catch (e) {
      if (mounted) {
        AppNotifications.error(
          context,
          t.sftp.createFailed(error: resolveSftpError(e, t)),
        );
      }
    }
  }

  void _submitPath(String value) {
    setState(() => _editing = false);
    final path = displayPathToSftp(value.trim());
    if (path.isNotEmpty) _load(path);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final canChoose = _canChooseHere;
    final desktop = isDesktopPlatform;
    final recent = widget.recent.where((r) => !sameSftpPath(r, _path)).toList();

    List<Widget> body(ScrollController? scrollController) => [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: _editing
                  ? TextField(
                      controller: _pathController,
                      autofocus: true,
                      style: colors.monoStyle.copyWith(
                        color: colors.textPrimary,
                        fontSize: 12,
                      ),
                      decoration: const InputDecoration(isDense: true),
                      onSubmitted: _submitPath,
                    )
                  : Text(
                      sftpPathToDisplay(_path),
                      style: colors.monoStyle.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            IconButton(
              tooltip: t.sftp.editPath,
              icon: Icon(
                PhosphorIconsRegular.pencilSimple,
                size: 18,
                color: colors.textTertiary,
              ),
              onPressed: () {
                _pathController.text = sftpPathToDisplay(_path);
                setState(() => _editing = !_editing);
              },
            ),
          ],
        ),
      ),
      if (recent.isNotEmpty)
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    t.sftp.recentFolders,
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                  ),
                ),
              ),
              for (final folder in recent)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(sftpPathToDisplay(folder)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _load(folder),
                  ),
                ),
            ],
          ),
        ),
      Divider(height: 1, color: colors.surfaceDivider),
      Expanded(child: _buildList(scrollController)),
      Divider(height: 1, color: colors.surfaceDivider),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
        child: Row(
          children: [
            Tooltip(
              message: AppCommands.tooltipFor(
                t.sftp.newFolder,
                SftpShortcuts.newFolder,
              ),
              child: TextButton.icon(
                onPressed: _loading || _error.isNotEmpty ? null : _createFolder,
                icon: const Icon(PhosphorIconsRegular.folderPlus, size: 18),
                label: Text(t.sftp.newFolder),
              ),
            ),
            const Spacer(),
            if (desktop && widget.onChoose == null) ...[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t.common.cancel),
              ),
              const SizedBox(width: 8),
            ],
            Tooltip(
              message: AppCommands.tooltipFor(
                widget.actionLabel,
                SftpShortcuts.chooseHere,
              ),
              child: FilledButton(
                onPressed: canChoose ? () => _choose(_path) : null,
                child: Text(widget.actionLabel),
              ),
            ),
          ],
        ),
      ),
    ];

    if (widget.onChoose != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: body(null),
          ),
        ),
      );
    }

    return AppDraggableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        if (desktop) {
          return Focus(
            focusNode: _keysFocus,
            autofocus: true,
            onKeyEvent: _onKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...body(scrollController),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(topPadding: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...body(scrollController),
          ],
        );
      },
    );
  }

  void _choose(String path) {
    if (widget.onChoose case final choose?) {
      choose(path);
      return;
    }
    Navigator.of(context).pop(path);
  }

  /// A phone opens a folder on a tap. A desktop's rows are a file dialog's:
  /// tight, a click puts the cursor on one and a second opens it.
  Widget _buildList(ScrollController? scrollController) {
    final colors = context.colors;
    final desktop = isDesktopPlatform;
    final rows = _rows;
    if (_loading && _folders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_error, style: TextStyle(color: colors.error)),
        ),
      );
    }
    return Column(
      children: [
        if (_loading)
          LinearProgressIndicator(minHeight: 2, color: colors.primary),
        Expanded(
          child: ListView.builder(
            controller: _listScroll = scrollController ?? _ownScroll,
            padding: EdgeInsets.zero,
            itemExtent: desktop ? _desktopRowHeight : null,
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return _FolderRow(
                name: row.name,
                icon: row.up
                    ? PhosphorIconsFill.folderOpen
                    : PhosphorIconsFill.folder,
                enabled: row.enabled,
                dense: desktop,
                selected: desktop && _cursor == index,
                onTap: desktop
                    ? () => _onDesktopClick(index)
                    : () => _load(row.path),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.dense = false,
    this.selected = false,
  });

  final String name;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool dense;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : colors.primary.invisible,
        child: InkWell(
          onTap: enabled || dense ? onTap : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 20,
              vertical: dense ? 0 : 12,
            ),
            child: Row(
              children: [
                Icon(icon, color: colors.primary, size: dense ? 18 : 22),
                SizedBox(width: dense ? 10 : 14),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: dense ? 13 : 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
