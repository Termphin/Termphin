import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../screens/sftp/sftp_editor_screen.dart';
import '../../screens/sftp/sftp_image_preview_screen.dart';
import '../../services/settings/sftp_settings.dart';
import '../../services/sftp/cancel_token.dart';
import '../../services/sftp/download_service.dart';
import '../../services/sftp/remote_path.dart';
import '../../services/sftp/sftp_remote_ops.dart';
import '../../services/sftp/sftp_service.dart';
import '../../services/sftp/transfer_queue.dart';
import '../../theme/theme.dart';
import '../../utils/file_type.dart';
import '../../utils/platform_info.dart';
import '../../utils/sftp_error_handler.dart';
import '../../utils/sftp_path.dart';
import '../../utils/text_sniffer.dart';
import '../terminal/terminal_scheme_theme.dart';
import '../ui/app_divider.dart';
import '../ui/app_dropdown.dart';
import '../ui/app_notifications.dart';
import '../ui/clipboard_and_links.dart';
import '../ui/confirm_dialog.dart';
import '../ui/text_input_dialog.dart';
import 'sftp_file_actions_menu.dart';
import 'sftp_file_row.dart';
import 'sftp_folder_picker.dart';
import 'sftp_path_bar.dart';
import 'sftp_selection_bar.dart';
import 'sftp_sort_sheet.dart';
import 'transfer_conflict_dialog.dart';

enum _AddAction { upload, newFolder, newFile }

class SftpBrowserView extends StatefulWidget {
  const SftpBrowserView({
    super.key,
    required this.session,
    this.transferQueue,
    this.terminalDirectory,
  });
  final ActiveSessionView session;

  /// Where uploads, downloads, copies and moves wait their turn - the
  /// session's, so they outlive the browser being out of sight. Without one
  /// the browser keeps a queue of its own.
  final TransferQueue? transferQueue;

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
  bool get _selectionMode => _selected.isNotEmpty;

  /// The last few copy and move destinations per machine, for the picker.
  /// Memory only: a folder picked last week is as likely gone as useful.
  static final Map<String, List<String>> _recentDestinations = {};

  @visibleForTesting
  static void clearRecentDestinations() => _recentDestinations.clear();

  TransferQueue? _ownQueue;

  TransferQueue get _queue =>
      widget.transferQueue ?? (_ownQueue ??= TransferQueue());

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
    sftpShowHiddenSetting.removeListener(_onShowHiddenChanged);
    for (final opener in _fileMenuOpeners.values) {
      opener.dispose();
    }
    unawaited(_sftp?.close());
    _ownQueue?.dispose();
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

  /// Overwrite prompts have to come before the progress dialog, or a modal
  /// would be asking a question from behind another modal.
  Future<void> _uploadFile() async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    final files = result.where((f) => f.path != null).toList();
    if (files.isEmpty || !mounted) return;

    final t = Translations.of(context);
    final planned = <PlatformFile>[];
    for (final file in files) {
      final remotePath = _joinPath(file.name);
      if (_sftp != null && await _sftp!.exists(remotePath)) {
        if (!mounted) return;
        if (await _confirmOverwrite(file.name) != true) continue;
      }
      planned.add(file);
    }
    if (planned.isEmpty || !mounted) return;

    var knownTotal = 0;
    for (final file in planned) {
      knownTotal += await file.length() ?? 0;
    }
    final sftp = _sftp;
    if (sftp == null || !mounted) return;
    final directory = _currentPath;
    var uploadedAny = false;
    try {
      await _queue.add<void>(
        kind: TransferJobKind.upload,
        label: planned.first.name,
        run: (job) async {
          var bytesBefore = 0;
          for (var i = 0; i < planned.length; i++) {
            job.cancel.throwIfCancelled();
            final file = planned[i];
            var sent = 0;
            await sftp.uploadFile(
              file.path!,
              joinRemotePath(directory, file.name),
              cancel: job.cancel,
              onProgress: (uploaded, _) {
                sent = uploaded;
                final overall = bytesBefore + uploaded;
                job.report(
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
        },
      );
    } catch (e) {
      if (mounted) {
        if (e is TransferCancelled) {
          AppNotifications.info(context, t.sftp.uploadCancelled);
        } else {
          AppNotifications.error(context, resolveSftpError(e, t));
        }
      }
    }
    if (uploadedAny && mounted) await _loadDirectory();
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
          : (isIOSPlatform ? t.sftp.shareDownload : t.sftp.openDownload),
      onAction: saved.uri == null
          ? null
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

  /// Downloads one entry - a file straight through, a directory walked and
  /// copied file by file.
  Future<void> _downloadFile(SftpName item) async {
    final sftp = _sftp;
    if (sftp == null) return;
    final remotePath = _joinPath(item.filename);

    await _runDownload(
      label: item.filename,
      run: (job) => item.attr.isDirectory
          ? DownloadService.downloadSftpDirectory(
              sftp: sftp,
              remotePath: remotePath,
              folderName: item.filename,
              cancel: job.cancel,
              onProgress: job.report,
            )
          : DownloadService.downloadSftpFile(
              sftp: sftp,
              remotePath: remotePath,
              fileName: item.filename,
              cancel: job.cancel,
              onProgress: job.report,
            ),
    );
  }

  Future<void> _downloadSelected() async {
    final sftp = _sftp;
    final items = _items.where((i) => _selected.contains(i.filename)).toList();
    if (sftp == null || items.isEmpty) return;
    _clearSelection();
    final t = Translations.of(context);
    final parentPath = _currentPath;
    final entries = [
      for (final item in items)
        SftpEntryRef(
          name: item.filename,
          isDirectory: item.attr.isDirectory,
          size: item.attr.size,
        ),
    ];

    await _runDownload(
      label: items.first.filename,
      run: (job) => DownloadService.downloadSftpSelection(
        sftp: sftp,
        parentPath: parentPath,
        entries: entries,
        multiFileLabel: t.sftp.downloadsFolder,
        cancel: job.cancel,
        onProgress: job.report,
      ),
    );
  }

  /// The one place a download is queued and reported: a cancelled transfer
  /// is reported as cancelled rather than as a failure. Paths are settled
  /// before the job is queued, since the browser may have moved on by the
  /// time it runs.
  Future<void> _runDownload({
    required String label,
    required Future<SavedDownload?> Function(TransferJob job) run,
  }) async {
    final t = Translations.of(context);
    try {
      final saved = await _queue.add(
        kind: TransferJobKind.download,
        label: label,
        run: run,
      );
      if (!mounted || saved == null) return;
      _announceSaved(saved);
    } catch (e) {
      if (!mounted) return;
      if (e is TransferCancelled) {
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
    if (sftp == null || items.isEmpty) return;
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
      sourceDirectory: sourceDirectory,
      entries: entries,
      destination: destination,
      choice: choice,
      move: move,
    );
  }

  Future<void> _duplicate(SftpName item) async {
    if (_sftp == null) return;
    await _runTransfers(
      sourceDirectory: _currentPath,
      entries: _entriesOf([item]),
      destination: _currentPath,
      choice: ConflictChoice.keepBoth,
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

  /// Cannot be cancelled once running: stopping `cp` halfway leaves half a
  /// folder, and closing the channel does not reliably stop it anyway. It
  /// can still be taken off the queue before it starts.
  ///
  /// The destination is listed and the names planned when the job starts,
  /// not when it is queued: a copy queued behind another into the same
  /// folder must not pick the name the first one is about to take.
  ///
  /// One failure does not strand the rest, as with delete - except when the
  /// account has no shell to run `cp`/`mv` on, since nothing after that can
  /// go either.
  Future<void> _runTransfers({
    required String sourceDirectory,
    required List<RemoteEntry> entries,
    required String destination,
    required ConflictChoice choice,
    required bool move,
  }) async {
    final t = Translations.of(context);
    final sftp = _sftp;
    if (sftp == null) return;

    TransferPlan? plan;
    Map<String, Object> failures = const {};
    try {
      await _queue.add<void>(
        kind: move ? TransferJobKind.move : TransferJobKind.copy,
        label: entries.length == 1
            ? entries.single.name
            : t.sftp.queue.items(count: entries.length),
        cancellable: false,
        run: (job) async {
          final listing = await sftp.listDirectory(destination);
          final planned = planTransfers(
            sourceDirectory: sourceDirectory,
            entries: entries,
            destination: destination,
            existing: {for (final e in listing) e.filename},
            choice: choice,
          );
          plan = planned;
          final failed = <String, Object>{};
          for (final (i, transfer) in planned.transfers.indexed) {
            job.report(
              TransferProgress(
                label: transfer.entry.name,
                itemIndex: i + 1,
                itemCount: planned.transfers.length,
                fraction: i / planned.transfers.length,
              ),
            );
            try {
              if (transfer.replaceExisting) await sftp.clearPath(transfer.to);
              if (move) {
                await sftp.moveEntry(transfer.from, transfer.to);
              } else {
                await sftp.copyEntry(transfer.from, transfer.to);
              }
            } catch (e) {
              failed[transfer.entry.name] = e;
              if (sftp.canRunCommands == false) break;
            }
          }
          if (failed.isNotEmpty) throw _TransferFailures(failed);
        },
      );
    } on _TransferFailures catch (e) {
      failures = e.failures;
    } on TransferCancelled {
      if (mounted) AppNotifications.info(context, t.sftp.queue.cancelled);
      return;
    } catch (e) {
      if (mounted) AppNotifications.error(context, resolveSftpError(e, t));
      return;
    }
    if (mounted) await _loadDirectory(showSpinner: false);
    final ran = plan;
    if (!mounted || ran == null) return;
    if (ran.transfers.isEmpty) {
      AppNotifications.info(context, t.sftp.nothingTransferred);
      return;
    }

    if (failures.isEmpty) {
      final done = ran.transfers.length;
      final name = ran.transfers.first.to.split('/').last;
      var message = switch ((move, done)) {
        (true, 1) => t.sftp.movedName(name: name),
        (true, _) => t.sftp.movedCount(count: done),
        (false, 1) => t.sftp.copiedName(name: name),
        (false, _) => t.sftp.copiedCount(count: done),
      };
      if (ran.skipped > 0) {
        message = '$message  ·  ${t.sftp.skippedCount(count: ran.skipped)}';
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalSchemeTheme(
          child: SftpEditorScreen(
            session: widget.session,
            fileItem: item,
            path: _joinPath(item.filename),
            sftp: _sftp,
          ),
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
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
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
                transferQueue: _queue,
              ),
            ),
          ),
        )
        .then((_) {
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
                  onSort: _showSortMenu,
                  onToggleHidden: () => unawaited(_toggleShowHidden()),
                  onEditingChanged: (editing) =>
                      setState(() => _editingPath = editing),
                  trailing: _sftp != null ? _buildAddButton() : null,
                ),
          const AppDivider(),
          Expanded(
            child: Stack(
              children: [
                _buildList(),
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
          ),
        ),
        DropdownItem(
          value: _AddAction.newFile,
          intrinsicHeight: true,
          child: AppDropdownItem(
            icon: PhosphorIconsFill.filePlus,
            label: t.sftp.newFile,
          ),
        ),
      ],
      child: SizedBox.square(
        dimension: 40,
        child: Icon(
          PhosphorIconsRegular.plus,
          color: _accent,
          size: AppTheme.icon22,
        ),
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

  Widget _buildList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space20),
          child: Text(_error, style: TextStyle(color: _errorColor)),
        ),
      );
    }
    return Column(
      children: [
        if (_isRefreshing)
          LinearProgressIndicator(
            minHeight: 2,
            color: _accent,
            backgroundColor: _surface.invisible,
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadDirectory(showSpinner: false),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _items.length,
              itemBuilder: (context, index) => _buildItem(_items[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItem(SftpName item) {
    final isUp = item.filename == '..';
    final path = _joinPath(item.filename);
    return SftpFileRow(
      item: item,
      path: path,
      isSelected: _selected.contains(item.filename),
      selectionMode: _selectionMode,
      isProbing: _probingPaths.contains(path),
      probe: _textProbes[path],
      runProbe: () => _probeText(item),
      opener: _menuOpenerFor(path),
      copyAvailable: _copyAvailable,
      onTap: () {
        if (_selectionMode && !isUp) {
          _toggleSelected(item.filename);
          return;
        }
        _navigateTo(item);
      },
      onLongPress: () {
        if (isUp) return;
        _toggleSelected(item.filename);
      },
      onAction: (action) => _handleFileAction(action, item, path),
    );
  }
}

/// The copies and moves of one job that failed, by entry name. Reads as the
/// first error, which is what the transfer list shows for the job.
class _TransferFailures implements Exception {
  const _TransferFailures(this.failures);

  final Map<String, Object> failures;

  @override
  String toString() => failures.values.first.toString();
}
