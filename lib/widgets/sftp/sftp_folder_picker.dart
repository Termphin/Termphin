import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/sftp/sftp_remote_ops.dart';
import '../../services/sftp/sftp_service.dart';
import '../../theme/theme.dart';
import '../../utils/sftp_error_handler.dart';
import '../../utils/sftp_path.dart';
import '../ui/app_notifications.dart';
import '../ui/app_sheet.dart';
import '../ui/sheet_handle.dart';
import '../ui/text_input_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _load(widget.startPath);
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
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
      });
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
    final canChoose = !_loading && _error.isEmpty && widget.canChoose(_path);
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
            TextButton.icon(
              onPressed: _loading || _error.isNotEmpty ? null : _createFolder,
              icon: const Icon(PhosphorIconsRegular.folderPlus, size: 18),
              label: Text(t.sftp.newFolder),
            ),
            const Spacer(),
            FilledButton(
              onPressed: canChoose ? () => _choose(_path) : null,
              child: Text(widget.actionLabel),
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

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
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
      ),
    );
  }

  void _choose(String path) {
    if (widget.onChoose case final choose?) {
      choose(path);
      return;
    }
    Navigator.of(context).pop(path);
  }

  Widget _buildList(ScrollController? scrollController) {
    final colors = context.colors;
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
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              if (!_atRoot)
                _FolderRow(
                  name: '..',
                  icon: PhosphorIconsFill.folderOpen,
                  enabled: true,
                  onTap: () => _load(sftpParentPath(_path)),
                ),
              for (final folder in _folders)
                Builder(
                  builder: (context) {
                    final path = joinSftpPath(_path, folder.filename);
                    final enabled = widget.canEnter(path);
                    return _FolderRow(
                      name: folder.filename,
                      icon: PhosphorIconsFill.folder,
                      enabled: enabled,
                      onTap: () => _load(path),
                    );
                  },
                ),
            ],
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
  });

  final String name;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: colors.primary, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
