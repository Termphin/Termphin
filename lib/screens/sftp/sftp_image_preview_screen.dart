import 'dart:async';

import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/sftp/cancel_token.dart';
import '../../services/sftp/download_service.dart';
import '../../services/sftp/sftp_service.dart';
import '../../theme/theme.dart';
import '../../utils/format_size.dart';
import '../../utils/sftp_error_handler.dart';
import '../../utils/sftp_path.dart';
import '../../widgets/sftp/transfer_progress_dialog.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/app_sheet.dart';
import '../../widgets/ui/clipboard_and_links.dart';
import '../../widgets/ui/confirm_dialog.dart';

class _ImageEntry {
  final String path;
  final String filename;
  final int? size;
  final int? mtime;
  const _ImageEntry({
    required this.path,
    required this.filename,
    this.size,
    this.mtime,
  });
}

class _PageState {
  File? file;
  bool isLoading = true;
  CancelToken cancel = CancelToken();
  double progress = 0;
  String error = '';
}

/// Full-screen image gallery with swipe navigation between the image files
/// that live alongside [initialPath] in the same directory. Opened as a
/// window on a desktop, where its leading button closes it rather than
/// backing out.
class SftpImagePreviewScreen extends StatefulWidget {
  final SftpService sftp;
  final String path;
  final String filename;
  final int? fileSize;
  final int? modifyTime;
  final String? directoryPath;
  final List<SftpName>? siblingImages;

  /// Called the moment an image is deleted from here, so the listing behind
  /// this screen can refresh itself on the way back.
  ///
  /// It is a callback rather than a pop result because returning one meant
  /// `canPop: false`, and a route that might veto its own pop gets no
  /// predictive-back preview from the system - the gesture animated nothing
  /// while the handler popped anyway.
  final VoidCallback? onMutated;

  const SftpImagePreviewScreen({
    super.key,
    required this.sftp,
    required this.path,
    required this.filename,
    this.fileSize,
    this.modifyTime,
    this.directoryPath,
    this.siblingImages,
    this.onMutated,
  });

  @override
  State<SftpImagePreviewScreen> createState() => _SftpImagePreviewScreenState();
}

class _SftpImagePreviewScreenState extends State<SftpImagePreviewScreen>
    with SingleTickerProviderStateMixin {
  /// 25 MB.
  static const _maxPreviewBytes = 25 * 1024 * 1024;

  late final List<_ImageEntry> _entries;
  late int _index;
  late final PageController _pageController;
  final Map<int, _PageState> _pages = {};
  final Map<int, TransformationController> _zoomControllers = {};
  final Set<int> _zoomListenersAttached = {};
  bool _zoomedIn = false;
  AnimationController? _zoomAnimController;
  Offset? _doubleTapLocalPosition;

  @override
  void initState() {
    super.initState();
    unawaited(
      AnalyticsService.instance.screen(AnalyticsScreen.sftpImagePreview),
    );
    _entries = _buildEntries();
    _index = _entries.indexWhere((e) => e.path == widget.path);
    if (_index < 0) _index = 0;
    _pageController = PageController(initialPage: _index);
  }

  List<_ImageEntry> _buildEntries() {
    final siblings = widget.siblingImages;
    final dir = widget.directoryPath;
    if (siblings == null || dir == null) {
      return [
        _ImageEntry(
          path: widget.path,
          filename: widget.filename,
          size: widget.fileSize,
          mtime: widget.modifyTime,
        ),
      ];
    }
    final base = dir.endsWith('/') ? dir : '$dir/';
    return siblings
        .map(
          (s) => _ImageEntry(
            path: '$base${s.filename}',
            filename: s.filename,
            size: s.attr.size,
            mtime: s.attr.modifyTime,
          ),
        )
        .toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded(_index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _zoomControllers.values) {
      c.dispose();
    }
    _zoomAnimController?.dispose();
    _cleanupTempFiles();
    super.dispose();
  }

  void _cleanupTempFiles() {
    for (final page in _pages.values) {
      final f = page.file;
      if (f != null) {
        f.exists().then((exists) {
          if (exists) f.delete().catchError((_) => f);
        });
      }
    }
  }

  _PageState _stateFor(int index) => _pages.putIfAbsent(index, _PageState.new);

  TransformationController _zoomFor(int index) {
    final controller = _zoomControllers.putIfAbsent(
      index,
      TransformationController.new,
    );
    if (_zoomListenersAttached.add(index)) {
      controller.addListener(() => _handleZoomChange(index, controller));
    }
    return controller;
  }

  void _handleZoomChange(int index, TransformationController controller) {
    if (index != _index) return;
    final zoomed = controller.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomedIn) setState(() => _zoomedIn = zoomed);
  }

  void _ensureLoaded(int index) {
    if (index < 0 || index >= _entries.length) return;
    final state = _stateFor(index);
    if (state.file != null || state.error.isNotEmpty) return;
    _loadImage(index);
  }

  /// Starts a fresh cancel token for the load: a token only fires once, so a
  /// retry after a cancel needs a new one.
  Future<void> _loadImage(int index) async {
    final entry = _entries[index];
    final state = _stateFor(index);

    if (entry.size != null && entry.size! > _maxPreviewBytes) {
      setState(() {
        state.isLoading = false;
        state.error = t.sftp.fileTooLarge(size: formatFileSize(entry.size));
      });
      return;
    }

    setState(() {
      state.isLoading = true;
      state.error = '';
      state.progress = 0;
      state.cancel = CancelToken();
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final key = Object.hash(entry.path, entry.mtime, entry.size);
      final ext = entry.filename.contains('.')
          ? entry.filename.substring(entry.filename.lastIndexOf('.'))
          : '';
      final localPath = '${tempDir.path}/sftp_img_${key.toUnsigned(32)}$ext';

      final existing = File(localPath);
      if (await existing.exists()) {
        if (!mounted) return;
        setState(() {
          state.file = existing;
          state.isLoading = false;
        });
        return;
      }

      await widget.sftp.downloadFile(
        entry.path,
        localPath,
        cancel: state.cancel,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            state.progress = total == null || total <= 0
                ? 0
                : (received / total).clamp(0.0, 1.0);
          });
        },
      );
      if (!mounted) return;
      setState(() {
        state.file = File(localPath);
        state.isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        state.error = state.cancel.isCancelled
            ? t.sftp.errors.cancelled
            : resolveSftpError(e, Translations.of(context));
        state.isLoading = false;
      });
    }
  }

  void _onPageChanged(int index) {
    final c = _zoomControllers[index];
    setState(() {
      _index = index;
      _zoomedIn = c != null && c.value.getMaxScaleOnAxis() > 1.01;
    });
    _ensureLoaded(index);
    _ensureLoaded(index - 1);
    _ensureLoaded(index + 1);
  }

  Future<void> _download() async {
    final entry = _entries[_index];
    final session = TransferSession(
      kind: TransferKind.download,
      initialLabel: entry.filename,
    )..show(context);
    try {
      await DownloadService.downloadSftpFile(
        sftp: widget.sftp,
        remotePath: entry.path,
        fileName: entry.filename,
        cancel: session.cancel,
        onProgress: session.update,
      );
      session.close();
      if (mounted) {
        AppNotifications.success(
          context,
          t.sftp.downloadComplete(filename: entry.filename),
        );
      }
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

  Future<void> _delete() async {
    final entry = _entries[_index];
    final confirmed = await showConfirmDialog(
      context,
      title: t.sftp.deleteTitle,
      message: t.sftp.deleteConfirm(filename: entry.filename),
      confirmLabel: t.common.delete,
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await widget.sftp.deletePath(entry.path);
      widget.onMutated?.call();
      if (!mounted) return;
      setState(() {
        _entries.removeAt(_index);
        _pages.remove(_index);
        _zoomControllers.remove(_index);
      });
      if (_entries.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (_index >= _entries.length) _index = _entries.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pageController.jumpToPage(_index);
      });
    } catch (e) {
      if (mounted) AppNotifications.error(context, resolveSftpError(e, t));
    }
  }

  void _animateZoomTo(TransformationController controller, Matrix4 end) {
    _zoomAnimController?.dispose();
    final animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    final animation = Matrix4Tween(begin: controller.value, end: end).animate(
      CurvedAnimation(parent: animController, curve: Curves.easeOutCubic),
    );
    animation.addListener(() => controller.value = animation.value);
    _zoomAnimController = animController;
    animController.forward();
  }

  void _handleDoubleTap(int index) {
    final controller = _zoomFor(index);
    if (controller.value != Matrix4.identity()) {
      _animateZoomTo(controller, Matrix4.identity());
      return;
    }
    const scale = 2.5;
    final position = _doubleTapLocalPosition ?? Offset.zero;
    final zoomed = Matrix4.identity()
      ..translateByDouble(position.dx, position.dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1)
      ..translateByDouble(-position.dx, -position.dy, 0, 1);
    _animateZoomTo(controller, zoomed);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final entry = _entries.isNotEmpty ? _entries[_index] : null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(
          icon: Icon(
            AppModalScope.isDialog(context)
                ? PhosphorIconsRegular.x
                : PhosphorIconsRegular.arrowLeft,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.surfaceBorder),
        ),
        title: entry == null
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.filename,
                    style: const TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      if (entry.size != null)
                        Text(
                          formatFileSize(entry.size),
                          style: context.colors.uiStyle.copyWith(
                            fontSize: 11,
                            color: context.colors.textTertiary,
                          ),
                        ),
                      if (_entries.length > 1) ...[
                        const SizedBox(width: 8),
                        Text(
                          t.sftp.imageCounter(
                            current: _index + 1,
                            total: _entries.length,
                          ),
                          style: context.colors.uiStyle.copyWith(
                            fontSize: 11,
                            color: context.colors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsFill.copy),
            tooltip: t.sftp.copyPath,
            onPressed: entry == null
                ? null
                : () => copyToClipboard(
                    context,
                    sftpPathToDisplay(entry.path),
                    message: t.sftp.pathCopied,
                  ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsFill.downloadSimple),
            tooltip: t.sftp.download,
            onPressed: entry != null && _stateFor(_index).file != null
                ? _download
                : null,
          ),
          IconButton(
            icon: const Icon(PhosphorIconsFill.trash),
            tooltip: t.common.delete,
            onPressed: entry == null ? null : _delete,
          ),
        ],
      ),
      body: _entries.isEmpty
          ? const SizedBox.shrink()
          : PageView.builder(
              controller: _pageController,
              itemCount: _entries.length,
              physics: _zoomedIn
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) => _buildPage(index),
            ),
    );
  }

  Widget _buildPage(int index) {
    final state = _stateFor(index);

    if (state.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
                color: context.colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            if (state.progress > 0)
              Text(
                '${(state.progress * 100).round()}%',
                style: TextStyle(color: context.colors.textSecondary),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(state.cancel.cancel),
              child: Text(
                t.sftp.cancel,
                style: TextStyle(color: context.colors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    if (state.error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsFill.imageBroken,
                color: context.colors.textTertiary,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                state.error,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onDoubleTapDown: (details) =>
          _doubleTapLocalPosition = details.localPosition,
      onDoubleTap: () => _handleDoubleTap(index),
      child: InteractiveViewer(
        transformationController: _zoomFor(index),
        minScale: 0.5,
        maxScale: 8.0,
        child: Center(
          child: Image.file(
            state.file!,
            key: ValueKey(state.file!.path),
            errorBuilder: (ctx, _, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIconsFill.imageBroken,
                    color: context.colors.textTertiary,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Translations.of(ctx).sftp.imageDecodeError,
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
