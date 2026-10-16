import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:re_editor/re_editor.dart' as re;

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/settings/editor_settings.dart';
import '../../services/sftp/sftp_service.dart';
import '../../theme/theme.dart';
import '../../utils/editor_languages.dart';
import '../../utils/editor_limits.dart';
import '../../utils/format_size.dart';
import '../../utils/sftp_error_handler.dart';
import '../../utils/sftp_path.dart';
import '../../widgets/sftp/code_editor_style.dart';
import '../../widgets/sftp/editor_find_bar.dart';
import '../../widgets/sftp/editor_selection_toolbar.dart';
import '../../widgets/terminal/pinch_font_zoom.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/empty_state.dart';

/// Files larger than this are shown without syntax highlighting to keep the
/// editor responsive.
const _kMaxHighlightChars = 1024 * 1024;

const _kLargeFileChunkLines = 1000;

class _DecodeResult {
  final String content;
  final String initialText;
  final List<String> lines;
  final bool isLarge;
  const _DecodeResult(this.content, this.initialText, this.lines, this.isLarge);
}

_DecodeResult _decodeAndSplit((Uint8List, int) args) {
  final (bytes, chunkLines) = args;
  final content = utf8.decode(bytes, allowMalformed: true);
  final lines = content.split('\n');
  final isLarge = lines.length > chunkLines;
  final initialText = isLarge
      ? lines.sublist(0, chunkLines.clamp(0, lines.length)).join('\n')
      : content;
  return _DecodeResult(content, initialText, lines, isLarge);
}

class SftpEditorScreen extends StatefulWidget {
  final ActiveSessionView session;
  final SftpName fileItem;
  final String path;
  final SftpService? sftp;

  const SftpEditorScreen({
    super.key,
    required this.session,
    required this.fileItem,
    required this.path,
    this.sftp,
  });

  @override
  State<SftpEditorScreen> createState() => _SftpEditorScreenState();
}

class _SftpEditorScreenState extends State<SftpEditorScreen> {
  late final SftpService _sftp;
  final _selectionToolbar = editorSelectionToolbar();

  /// The channel this screen opened itself; one handed in is the browser's.
  SftpService? _ownSftp;
  late final ScrollController _verticalScrollController;
  late final re.CodeScrollController _editorScrollController;
  re.CodeLineEditingController? _ctrl;
  re.CodeFindController? _find;
  bool _isLoading = true;
  bool _isSaving = false;
  String _error = '';
  String _originalContent = '';
  bool _isLargeFileMode = false;
  bool _largeModeDirty = false;
  List<String> _allLines = <String>[];
  int _windowStartLine = 0;

  /// Exclusive.
  int _windowEndLine = 0;
  String _windowOriginalText = '';
  bool _isEditorAtBottom = false;
  bool _isLoadingMore = false;

  /// The live size while a pinch is under way; the setting only takes the
  /// size a pinch settles on.
  double _fontSize = editorSettings.fontSize.value;
  Timer? _fontSizeSave;
  int? _loadedMtime;

  /// Whether the buffer differs from what is on the server, cached rather
  /// than recomputed on demand: working it out reads `controller.text`,
  /// which joins every line of the file into a fresh string, and [build]
  /// asks three times (the pop guard, Save's colour, Save's callback).
  bool _isDirty = false;

  /// The line set the cached flag was computed against. The editor notifies
  /// on selection and composing changes too, and those carry the same
  /// instance through - so moving the caret costs nothing here.
  Object? _dirtyCheckedAgainst;

  /// The route's own push transition, held only while [_onRouteAnimationDone]
  /// is still listening to it - set once `didChangeDependencies` attaches the
  /// listener, so a later call does not attach a second one, and [dispose]
  /// has something to detach even if the animation never completed.
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.sftpEditor));
    editorSettings.changes.addListener(_onSettingsChanged);
    _verticalScrollController = ScrollController()
      ..addListener(_handleEditorScroll);
    _editorScrollController = re.CodeScrollController(
      verticalScroller: _verticalScrollController,
    );
    if (widget.sftp != null) {
      _sftp = widget.sftp!;
    } else {
      unawaited(_initSftp());
    }
  }

  Future<void> _initSftp() async {
    try {
      final session = widget.session;
      _sftp = _ownSftp = SftpService.resolving(() => session.sftpClient);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isLoading || _ctrl != null || _error.isNotEmpty) return;
    if (_routeAnimation != null) return;
    final route = ModalRoute.of(context);
    if (route == null || route.animation!.isCompleted) {
      _loadFile();
    } else {
      _routeAnimation = route.animation;
      _routeAnimation!.addStatusListener(_onRouteAnimationDone);
    }
  }

  void _onRouteAnimationDone(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeAnimation?.removeStatusListener(_onRouteAnimationDone);
    _routeAnimation = null;
    if (mounted && _isLoading && _ctrl == null) _loadFile();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() => _fontSize = editorSettings.fontSize.value);
  }

  void _openFind() {
    final find = _find!;
    find.findMode();
    find.focusOnFindInput();
  }

  void _toggleWordWrap() =>
      unawaited(editorSettings.wordWrap.set(!editorSettings.wordWrap.value));

  /// A pinch is a stream of sizes; only where it settles is worth a write.
  void _onPinch(double size) {
    setState(() => _fontSize = size);
    _fontSizeSave?.cancel();
    _fontSizeSave = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(editorSettings.fontSize.set(size)),
    );
  }

  /// Repaints the chrome that depends on the text - whether Save is enabled
  /// and whether back has to ask first.
  ///
  /// Only when that answer actually changes. Rebuilding on every notification
  /// redrew the whole screen, `CodeEditor` included, once per keystroke and
  /// once per caret move; there are two moments worth a repaint in an editing
  /// session, the first edit and a save.
  ///
  /// The editor notifies while it is itself building, and a plain `setState`
  /// there is "setState() called during build". Deferring only in that phase
  /// keeps the ordinary keystroke path a same-frame repaint.
  void _handleEditorChanged() {
    if (!mounted) return;
    final lines = _ctrl?.value.codeLines;
    if (identical(lines, _dirtyCheckedAgainst)) return;
    _dirtyCheckedAgainst = lines;
    if (!_refreshDirty()) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  /// Recomputes [_isDirty]. Returns whether it changed, so the caller can
  /// skip a repaint that would draw the same pixels.
  bool _refreshDirty() {
    final next = _computeDirty();
    if (next == _isDirty) return false;
    _isDirty = next;
    return true;
  }

  Future<void> _loadFile() async {
    try {
      try {
        final attrs = await _sftp.stat(widget.path);
        _loadedMtime = attrs.modifyTime;
        if (isTooLargeToEdit(attrs.size)) {
          if (!mounted) return;
          setState(() {
            _error = Translations.of(
              context,
            ).sftp.fileTooLargeToEdit(size: formatFileSize(attrs.size));
            _isLoading = false;
          });
          return;
        }
      } catch (_) {
        _loadedMtime = null;
      }

      final bytes = await _sftp.readFileBytes(widget.path);
      if (!mounted) return;

      final result = await compute(_decodeAndSplit, (
        bytes,
        _kLargeFileChunkLines,
      ));
      if (!mounted) return;

      _isLargeFileMode = result.isLarge;
      _allLines = result.isLarge ? result.lines : <String>[];
      _windowStartLine = 0;
      _windowEndLine = result.isLarge
          ? _kLargeFileChunkLines.clamp(0, result.lines.length)
          : 0;

      final ctrl = re.CodeLineEditingController.fromText(
        result.initialText,
        re.CodeLineOptions(indentSize: editorSettings.tabWidth.value),
      );
      ctrl.addListener(_handleEditorChanged);

      setState(() {
        _ctrl = ctrl;
        _find = re.CodeFindController(ctrl);
        _originalContent = result.content;
        _windowOriginalText = result.initialText;
        _largeModeDirty = false;
        _isDirty = false;
        _dirtyCheckedAgainst = ctrl.value.codeLines;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateEditorAtBottom();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = resolveSftpError(e, Translations.of(context));
          _isLoading = false;
        });
      }
    }
  }

  void _syncWindowToAllLines() {
    if (!_isLargeFileMode || _ctrl == null) return;
    if (_ctrl!.text == _windowOriginalText) return;

    final replacement = _ctrl!.text.split('\n');
    _allLines.replaceRange(_windowStartLine, _windowEndLine, replacement);
    _windowEndLine = _windowStartLine + replacement.length;
    _windowOriginalText = _ctrl!.text;
    _largeModeDirty = true;
  }

  /// Extends the visible window downward in a large file. The dirty flag is
  /// reset against the new window's text, since the listener that set it has
  /// already run against the window this replaces - what it flagged is text
  /// no longer on screen.
  void _loadMoreLinesDown() {
    if (!_isLargeFileMode ||
        _ctrl == null ||
        _windowEndLine >= _allLines.length) {
      return;
    }
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    _syncWindowToAllLines();

    final savedPixels = _verticalScrollController.hasClients
        ? _verticalScrollController.position.pixels
        : 0.0;

    _windowEndLine = (_windowEndLine + _kLargeFileChunkLines).clamp(
      0,
      _allLines.length,
    );
    final nextText = _allLines
        .sublist(_windowStartLine, _windowEndLine)
        .join('\n');
    _ctrl!.text = nextText;
    _windowOriginalText = nextText;
    _dirtyCheckedAgainst = _ctrl!.value.codeLines;
    _refreshDirty();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_verticalScrollController.hasClients) {
        _verticalScrollController.jumpTo(savedPixels);
      }
      _isLoadingMore = false;
      _updateEditorAtBottom();
      setState(() {});
    });
  }

  void _handleEditorScroll() {
    _updateEditorAtBottom();
    if (_isEditorAtBottom &&
        _isLargeFileMode &&
        _windowEndLine < _allLines.length) {
      _loadMoreLinesDown();
    }
  }

  void _updateEditorAtBottom() {
    if (!_verticalScrollController.hasClients) return;
    final pos = _verticalScrollController.position;
    final isAtBottom = pos.pixels >= (pos.maxScrollExtent - 40);
    if (isAtBottom != _isEditorAtBottom) {
      _isEditorAtBottom = isAtBottom;
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteAnimationDone);
    editorSettings.changes.removeListener(_onSettingsChanged);
    unawaited(_ownSftp?.close());
    _fontSizeSave?.cancel();
    _find?.dispose();
    _ctrl?.dispose();
    _editorScrollController.dispose();
    _verticalScrollController
      ..removeListener(_handleEditorScroll)
      ..dispose();
    super.dispose();
  }

  bool get _hasWindowChanges =>
      _ctrl != null && _ctrl!.text != _windowOriginalText;

  bool get _hasChanges => _isDirty;

  bool _computeDirty() {
    if (_ctrl == null) return false;
    if (!_isLargeFileMode) return _ctrl!.text != _originalContent;
    return _largeModeDirty || _hasWindowChanges;
  }

  Future<bool> _confirmOverwriteRemoteChange() async {
    return showConfirmDialog(
      context,
      title: t.editor.modifiedRemotelyTitle,
      message: t.editor.modifiedRemotelyBody,
      confirmLabel: t.editor.saveAnyway,
      destructive: true,
    );
  }

  Future<void> _saveFile() async {
    if (_ctrl == null) return;
    setState(() => _isSaving = true);
    try {
      if (_loadedMtime != null) {
        int? currentMtime;
        try {
          currentMtime = (await _sftp.stat(widget.path)).modifyTime;
        } catch (_) {
          currentMtime = null;
        }
        if (currentMtime != null && currentMtime != _loadedMtime) {
          final proceed = await _confirmOverwriteRemoteChange();
          if (!proceed) {
            if (mounted) setState(() => _isSaving = false);
            return;
          }
        }
      }

      if (_isLargeFileMode) {
        _syncWindowToAllLines();
      }
      final contentToSave = _isLargeFileMode
          ? _allLines.join('\n')
          : _ctrl!.text;
      await _sftp.writeStringToFile(widget.path, contentToSave);
      if (mounted) {
        _originalContent = contentToSave;
        if (_isLargeFileMode) {
          _windowOriginalText = _ctrl!.text;
          _largeModeDirty = false;
        }
        _refreshDirty();
        try {
          _loadedMtime = (await _sftp.stat(widget.path)).modifyTime;
        } catch (_) {}
        if (!mounted) return;
        AppNotifications.success(context, t.editor.savedSuccess);
      }
    } catch (e) {
      if (mounted) {
        AppNotifications.error(context, resolveSftpError(e, t));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    return showConfirmDialog(
      context,
      title: t.editor.unsavedTitle,
      message: t.editor.discardConfirm,
      confirmLabel: t.common.discard,
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: context.colors.backgroundPrimary,
        appBar: AppBar(
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(AppTheme.hairline),
            child: Container(
              height: AppTheme.hairline,
              color: context.colors.surfaceBorder,
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.fileItem.filename,
                style: const TextStyle(fontSize: AppTheme.font16),
              ),
              Text(
                sftpPathToDisplay(widget.path),
                style: context.colors.monoSmall.copyWith(
                  color: context.colors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (_find != null)
              IconButton(
                tooltip: Translations.of(context).editor.find,
                icon: const Icon(PhosphorIconsRegular.magnifyingGlass),
                onPressed: _openFind,
              ),
            IconButton(
              tooltip: Translations.of(context).editor.toggleWordWrap,
              icon: Icon(
                editorSettings.wordWrap.value
                    ? PhosphorIconsFill.textAlignLeft
                    : PhosphorIconsFill.arrowElbowDownLeft,
                color: editorSettings.wordWrap.value
                    ? context.colors.primary
                    : context.colors.textTertiary,
              ),
              onPressed: _toggleWordWrap,
            ),
            if (_isSaving)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppTheme.space16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: Translations.of(context).common.save,
                icon: Icon(
                  PhosphorIconsFill.floppyDisk,
                  color: _hasChanges
                      ? context.colors.primary
                      : context.colors.textTertiary,
                ),
                onPressed: _isLoading || _error.isNotEmpty || !_hasChanges
                    ? null
                    : _saveFile,
              ),
          ],
        ),
        body: SafeArea(top: false, child: _buildBody()),
      ),
    );
  }

  String get _extension {
    final name = widget.fileItem.filename.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1) : '';
  }

  Widget _buildCodeEditor() {
    final lang = editorLanguageForExtension(_extension);
    final highlight = _originalContent.length <= _kMaxHighlightChars;
    return PinchFontZoom(
      fontSize: _fontSize,
      min: kEditorMinFontSize,
      max: kEditorMaxFontSize,
      onChanged: _onPinch,
      child: re.CodeEditor(
        controller: _ctrl!,
        findController: _find,
        toolbarController: _selectionToolbar,
        findBuilder: (context, controller, readOnly) =>
            EditorFindBar(controller: controller, readOnly: readOnly),
        scrollController: _editorScrollController,
        wordWrap: editorSettings.wordWrap.value,
        style: codeEditorStyle(
          context,
          fontSize: _fontSize,
          language: highlight ? lang : null,
        ),
        padding: const EdgeInsets.all(AppTheme.space12),
        indicatorBuilder: editorLineNumbers(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyStatePanel(
        icon: PhosphorIconsFill.warningCircle,
        title: t.editor.error(error: _error),
        tone: EmptyStateTone.error,
        compact: true,
      );
    }

    return Column(
      children: [
        if (_isLargeFileMode)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space12,
              vertical: AppTheme.space8,
            ),
            decoration: BoxDecoration(
              color: context.colors.surfaceCard,
              border: Border(
                bottom: BorderSide(color: context.colors.surfaceBorder),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsFill.info,
                  size: AppTheme.icon12,
                  color: context.colors.textTertiary,
                ),
                const SizedBox(width: AppTheme.space6),
                Text(
                  t.editor.lines(
                    start: _windowStartLine + 1,
                    end: _windowEndLine,
                    total: _allLines.length,
                  ),
                  style: context.colors.uiStyle.copyWith(
                    fontSize: AppTheme.font12,
                    color: context.colors.textTertiary,
                  ),
                ),
                if (_windowEndLine < _allLines.length) ...[
                  const SizedBox(width: AppTheme.space6),
                  Text(
                    t.editor.scrollToLoadMore,
                    style: context.colors.uiStyle.copyWith(
                      fontSize: AppTheme.font12,
                      color: context.colors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        Expanded(child: _buildCodeEditor()),
        if (_isLargeFileMode &&
            _windowEndLine < _allLines.length &&
            _isLoadingMore)
          LinearProgressIndicator(
            minHeight: 2,
            color: context.colors.primary,
            backgroundColor: context.colors.surfaceBorder,
          ),
      ],
    );
  }
}
