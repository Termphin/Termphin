import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../models/remote_shell.dart';
import '../../models/session_tab.dart';
import '../../models/ssh_profile.dart';
import '../../providers/ssh_connection_provider.dart';
import '../../providers/ssh_session_manager_provider.dart';
import '../../services/completion/command_completion.dart';
import '../../services/settings/sftp_settings.dart';
import '../../services/settings/terminal_settings.dart';
import '../../services/settings/upload_settings.dart';
import '../../services/sftp/cancel_token.dart';
import '../../services/sftp/sftp_remote_ops.dart';
import '../../services/sftp/sftp_service.dart';
import '../../services/sftp/upload_plan.dart';
import '../../services/ssh/local_network_permission.dart';
import '../../services/ssh/ssh_service.dart';
import '../../services/ssh/ssh_session_manager.dart';
import '../../services/terminal/terminal_text.dart';
import '../../theme/theme.dart';
import '../../utils/connection_error_text.dart';
import '../../utils/platform_info.dart';
import '../../utils/sftp_error_handler.dart';
import '../../utils/sftp_path.dart';
import '../sftp/confirm_overwrite.dart';
import '../sftp/sftp_browser_view.dart';
import '../sftp/sftp_folder_picker.dart';
import '../sftp/upload_progress_bar.dart';
import '../ssh/connecting_view.dart';
import '../ssh/connection_log_sheet.dart';
import '../ssh/connection_quality_pill.dart';
import '../ui/app_notifications.dart';
import '../ui/clipboard_and_links.dart';
import '../ui/cursor_menu.dart';
import '../ui/manual_link.dart';
import 'command_suggestion_popup.dart';
import 'floating_action_dock.dart';
import 'link_preview_popup.dart';
import 'special_keys_toolbar.dart';
import 'terminal_pane.dart';

/// Whether a tab is showing its terminal or its file browser.
///
/// A property of the tab, not of the screen: one tab sitting in a file
/// browser says nothing about what the next one should show.
enum SessionViewMode { terminal, sftp }

class SessionView extends ConsumerStatefulWidget {
  const SessionView({
    super.key,
    required this.sessionKey,
    required this.viewMode,
    required this.isActive,
    required this.onClose,
    this.sftpKey,
  });

  final (String, SshProfile) sessionKey;
  final SessionViewMode viewMode;
  final bool isActive;
  final VoidCallback onClose;
  final GlobalKey<SftpBrowserViewState>? sftpKey;

  @override
  ConsumerState<SessionView> createState() => SessionViewState();
}

/// Readiness is tracked by `attachId` rather than connection status:
/// Riverpod can settle back on `connected` before Flutter ever paints the
/// frame in between, which would otherwise mean the terminal widget (keyed
/// on `attachId`) never tears down and its one-shot `onReady` callback
/// never fires again.
///
/// On a local-network failure, the permission button leads and Retry steps
/// back to an outline, since tapping Retry first only fails the same way
/// again.
class SessionViewState extends ConsumerState<SessionView> {
  final ValueNotifier<CtrlMode> ctrlMode = ValueNotifier(CtrlMode.off);
  final ValueNotifier<AltMode> altMode = ValueNotifier(AltMode.off);
  final ValueNotifier<ShiftMode> shiftMode = ValueNotifier(ShiftMode.off);
  final TerminalPaneController _nativeController = TerminalPaneController();

  /// Read through the provider rather than off the singleton, so every path in
  /// here talks to the same manager - `writeRaw` already went through it, and
  /// the two only agree by coincidence. In the app the provider hands back
  /// `SshSessionManager.instance` either way.
  SshSessionManager get _manager => ref.read(sshSessionManagerProvider);

  void focusTerminal() {
    _nativeController.focusTerminal();
  }

  /// A desktop has no keyboard to pop up, so the tab on screen takes the keys
  /// as soon as it can - otherwise the first thing typed into a session just
  /// opened, or switched to, went nowhere until it was clicked. Not past a
  /// dialog over it: a host key prompt keeps the keyboard it asked for.
  void _focusOnDesktop() {
    if (!isDesktopPlatform) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive || !_terminalReady) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      _nativeController.focusTerminal();
    });
  }

  void blurTerminal() {
    _nativeController.blurTerminal();
  }

  void pauseTerminal() {
    _nativeController.pause();
  }

  late final CommandCompletion _completion = CommandCompletion(
    hostKey: widget.sessionKey.$2.id,
    run: (command) => _manager.exec(widget.sessionKey.$1, command),
    windows: () => _remoteShell == RemoteShellType.powershell,
    location: _shellLocation,
  );

  RemoteShellType? get _remoteShell =>
      _manager.getSession(widget.sessionKey.$1)?.remoteShellType;

  Timer? _commandLineDebounce;

  /// The cursor cell the popup floats over.
  Rect? _suggestionRow;

  /// Set once a suggestion is taken or the popup closed: it stays away until
  /// the user types again, rather than offering the next thing at once.
  bool _suggestionsPaused = false;

  /// The suggestion the keyboard is on, best first; back to the best one
  /// whenever the list changes.
  int _suggestionPick = 0;

  bool get _suggestionsVisible =>
      widget.isActive &&
      !_scrollModeManual &&
      !_suggestionsPaused &&
      _suggestionRow != null &&
      _cursorMenuContent == null &&
      !_selectionPopupVisible &&
      _completion.suggestions.value.isNotEmpty;

  /// On a desktop the popup is worked from the keyboard: Ctrl+Up/Down move
  /// through it, Ctrl+Right takes the one picked, as a click does, and Esc
  /// closes it - Cmd on a Mac, whose Ctrl+arrows are the system's. Asked by
  /// the terminal before it sends a key on, so a key used here never reaches
  /// the shell; with the popup gone they are all the shell's again. The
  /// release of a key used here is not the shell's either, and Esc closes
  /// only this one popup - the next Esc is the shell's, and vim's, again.
  /// Up and down go as drawn: above the line the best one is at the bottom.
  KeyEventResult _onTerminalKey(FocusNode _, KeyEvent event) {
    if (!isDesktopPlatform || !_suggestionsVisible) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final mac = isMacOSPlatform;
    final escape =
        key == LogicalKeyboardKey.escape &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed;
    final held = mac
        ? keyboard.isMetaPressed && !keyboard.isControlPressed
        : keyboard.isControlPressed && !keyboard.isMetaPressed;
    final arrow =
        held &&
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowRight);
    if (!escape && !arrow) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.handled;
    if (escape) {
      if (event is KeyDownEvent) _dismissSuggestions();
      return KeyEventResult.handled;
    }
    final suggestions = _completion.suggestions.value;
    final count = suggestions.length < kMaxShownSuggestions
        ? suggestions.length
        : kMaxShownSuggestions;
    final pick = _suggestionPick.clamp(0, count - 1);
    if (key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent) _acceptSuggestion(suggestions[pick]);
      return KeyEventResult.handled;
    }
    final above = CommandSuggestionPopup.opensAbove(_suggestionRow!);
    final step = (key == LogicalKeyboardKey.arrowUp) == above ? 1 : -1;
    setState(() => _suggestionPick = (pick + step) % count);
    return KeyEventResult.handled;
  }

  void _acceptSuggestion(CommandSuggestion suggestion) {
    setState(() => _suggestionsPaused = true);
    writeRaw(
      Uint8List.fromList([
        for (var i = 0; i < suggestion.erase; i++) 0x7f,
        ...utf8.encode(suggestion.insert),
      ]),
    );
  }

  void _dismissSuggestions() => setState(() => _suggestionsPaused = true);

  void _onSuggestionsChanged() {
    if (mounted) setState(() => _suggestionPick = 0);
  }

  /// The screen changes on every write; the line is read once it settles.
  void _onScreenChanged() {
    _commandLineDebounce?.cancel();
    _commandLineDebounce = Timer(
      const Duration(milliseconds: 80),
      _refreshCommandLine,
    );
  }

  /// Drops the line when there is nothing typed yet, or something already
  /// drawn after the cursor - the rest of a line being edited, or the
  /// shell's own suggestion.
  void _refreshCommandLine() {
    if (!mounted) return;
    var line = _completionUsable && widget.isActive
        ? _nativeController.readCommandLine()
        : null;
    if (line != null &&
        (line.trim().isEmpty || _nativeController.textFollowsCursor())) {
      line = null;
    }
    final row = _nativeController.cursorRectInStack();
    if (row != _suggestionRow) setState(() => _suggestionRow = row);
    _completion.update(line);
  }

  /// Once the shell is known: sh scripts for Unix, PowerShell for Windows.
  bool get _completionUsable {
    final session = _manager.getSession(widget.sessionKey.$1);
    return commandSuggestionsSetting.value &&
        session != null &&
        !session.dropped &&
        session.remoteShellType != RemoteShellType.unknown;
  }

  void _onCommandSubmitted(String command) {
    if (_completionUsable) _completion.remember(command);
  }

  /// See [CommandCompletion.location]. Windows has nothing to read on the
  /// server, but its prompt reports the directory over an OSC marker.
  String? _shellLocation() {
    final session = _manager.getSession(widget.sessionKey.$1);
    if (session?.remoteShellType == RemoteShellType.powershell) {
      return session?.reportedCwd;
    }
    final muxName = session?.muxName;
    if (session?.multiplexer != Multiplexer.termphin || muxName == null) {
      return null;
    }
    return '.cache/termphin/sessions/$muxName/cwd';
  }

  bool _terminalReady = false;

  /// The terminal last shown live. Kept on screen through a reconnect, and
  /// over its replacement until that one is ready, so a drop reads as a
  /// pause rather than the session vanishing.
  ({ActiveSessionView session, int attachId})? _heldFrame;

  double _fontSize = kTerminalDefaultFontSize;
  bool _terminalSettingsLoaded = false;
  int? _readyAttachId;
  bool _selectionPopupVisible = false;
  double _selTopY = 0;
  double _selBottomY = 0;

  Offset? _cursorMenuAnchor;
  Widget? _cursorMenuContent;

  OverlayEntry? _linkOverlayEntry;
  double _lastPointerGlobalY = 0;
  bool _sftpInitialized = false;
  bool _scrollModeManual = false;
  StreamSubscription<void>? _rebootRestoredSub;

  /// On the first switch into the SFTP tab the browser is not built yet; it
  /// opens there itself, so [SftpBrowserViewState.followTerminal] is only
  /// called on later switches.
  ///
  /// Dismisses the keyboard when leaving a tab. Deliberately not the mirror
  /// image on the way back in - grabbing focus (and popping the keyboard)
  /// just for becoming active is exactly what shouldn't happen; that is
  /// reserved for an explicit tap on the terminal.
  @override
  void didUpdateWidget(covariant SessionView oldWidget) {
    if (widget.viewMode == SessionViewMode.sftp &&
        oldWidget.viewMode != SessionViewMode.sftp) {
      if (_sftpInitialized) {
        unawaited(widget.sftpKey?.currentState?.followTerminal());
      }
      _sftpInitialized = true;
    }
    if (!widget.isActive && oldWidget.isActive) {
      _nativeController.pause();
      _dismissCursorMenu();
    }
    if (widget.isActive && !oldWidget.isActive) _focusOnDesktop();
    if (widget.isActive != oldWidget.isActive) _onScreenChanged();
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  /// The font size setting is already loaded before the first frame, so
  /// there is nothing to await and no window where the terminal is drawn
  /// with the defaults first.
  @override
  void initState() {
    super.initState();
    if (widget.viewMode == SessionViewMode.sftp) _sftpInitialized = true;
    terminalSettings.changes.addListener(_onSettingsChanged);
    commandSuggestionsSetting.addListener(_refreshCommandLine);
    _completion.suggestions.addListener(_onSuggestionsChanged);
    _nativeController
      ..addScreenListener(_onScreenChanged)
      ..onCommandSubmitted = _onCommandSubmitted;
    _fontSize = terminalSettings.fontSize.value;
    _terminalSettingsLoaded = true;
  }

  @override
  void dispose() {
    _dismissLink();
    terminalSettings.changes.removeListener(_onSettingsChanged);
    commandSuggestionsSetting.removeListener(_refreshCommandLine);
    _nativeController.removeScreenListener(_onScreenChanged);
    _commandLineDebounce?.cancel();
    _completion.dispose();
    unawaited(_rebootRestoredSub?.cancel());
    _fontSizeSaveDebounce?.cancel();
    _resizeDebounce?.cancel();
    ctrlMode.dispose();
    altMode.dispose();
    shiftMode.dispose();
    _uploadCancel?.cancel();
    _uploadProgress.dispose();
    super.dispose();
  }

  void _ensureRebootRestoredListener(ActiveSessionView session) {
    if (_rebootRestoredSub != null) return;
    _rebootRestoredSub = session.rebootRestoredEvents.listen((_) {
      if (!mounted) return;
      AppNotifications.info(
        context,
        Translations.of(context).session.rebootRestored,
      );
    });
  }

  void _applySettings() {
    if (!_terminalReady) return;
    final settings = terminalSettings;
    _nativeController.setFontSize(_fontSize);
    _nativeController.setFontFamily(settings.fontFamily.value);
    _nativeController.setColors(
      AppTheme.terminalSchemeForId(settings.scheme.value),
    );
    _nativeController.setSidePadding(settings.sidePadding.value);
    _nativeController.setLineHeight(settings.lineHeight.value);
    _nativeController.setCursorStyle(settings.cursorStyle.value);
    _nativeController.setCursorBlink(settings.cursorBlink.value);
    _nativeController.setPredictiveEcho(settings.predictiveEcho.value);
  }

  /// The pinch zoom writes the same font size setting, so the notification
  /// comes back round to here - taking the stored value keeps the two in
  /// step either way, and `setState` is what repaints anything reading
  /// [_fontSize].
  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() => _fontSize = terminalSettings.fontSize.value);
    _applySettings();
  }

  void _onTerminalReady(int attachId) {
    _readyAttachId = attachId;
    _terminalReady = true;
    _manager.getSession(widget.sessionKey.$1)?.pendingReplay = null;
    _applySettings();
    _nativeController.requestFit();
    ref
        .read(sshConnectionProvider(widget.sessionKey).notifier)
        .flushQueuedInput();
    if (mounted) setState(() {});
    if (widget.isActive) _focusOnDesktop();
  }

  Timer? _fontSizeSaveDebounce;

  /// A pinch is a continuous stream of sizes; only the one it settles on is
  /// worth a write, so saving is debounced.
  void _onFontSizeChanged(double fontSize) {
    if (!mounted) return;
    final clamped = fontSize.clamp(kTerminalMinFontSize, kTerminalMaxFontSize);
    if ((_fontSize - clamped).abs() > 0.001) {
      setState(() => _fontSize = clamped);
    }

    _fontSizeSaveDebounce?.cancel();
    _fontSizeSaveDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(terminalSettings.fontSize.set(clamped)),
    );
  }

  /// Shows [contentBuilder]'s result anchored to the terminal cursor's
  /// current position - the general mechanism behind the "paste path after
  /// upload" menu, kept generic so a future menu at the cursor doesn't need
  /// its own positioning code. [contentBuilder] gets a dismiss callback to
  /// wire into its own close button or action taps.
  void _showCursorMenu(Widget Function(VoidCallback dismiss) contentBuilder) {
    final anchor = _nativeController.cursorOffsetInStack();
    if (anchor == null || !mounted) return;
    setState(() {
      _cursorMenuAnchor = anchor;
      _cursorMenuContent = contentBuilder(_dismissCursorMenu);
    });
  }

  void _dismissCursorMenu() {
    if (_cursorMenuContent == null) return;
    setState(() {
      _cursorMenuAnchor = null;
      _cursorMenuContent = null;
    });
  }

  /// Typing dismisses any menu anchored to the cursor, since it is about to
  /// move. Shift is a real modifier, not an arrow-key-only toggle: it also
  /// uppercases (and shifts the symbols of) whatever the soft keyboard
  /// types. Alt sends the key prefixed with ESC, the standard xterm Meta
  /// encoding. Some keyboards/IMEs emit LF for Enter, which is normalized to
  /// CR for interactive SSH shells. Typing brings closed suggestions back -
  /// but not a bare Esc, which is what closed them: pressed again it would
  /// open them right back, a toggle where it is meant to be a way out.
  void _onInput(List<int> rawBytes) {
    if (_cursorMenuContent != null) _dismissCursorMenu();
    if (isTypedInput(rawBytes)) _dismissLink();
    if (_suggestionsPaused &&
        isTypedInput(rawBytes) &&
        !(rawBytes.length == 1 && rawBytes[0] == 0x1b)) {
      setState(() => _suggestionsPaused = false);
    }
    var bytes = rawBytes;

    if (shiftMode.value != ShiftMode.off && bytes.length == 1) {
      final shifted = shiftedAsciiByte(bytes[0]);
      if (shifted != null) {
        bytes = [shifted];
        if (shiftMode.value == ShiftMode.oneshot) {
          shiftMode.value = ShiftMode.off;
        }
      }
    }

    if (altMode.value != AltMode.off && bytes.length == 1) {
      writeRaw(Uint8List.fromList([0x1b, bytes[0]]));
      if (altMode.value == AltMode.oneshot) {
        altMode.value = AltMode.off;
      }
      return;
    }

    if (ctrlMode.value == CtrlMode.off &&
        bytes.length == 1 &&
        bytes[0] == 0x0A) {
      writeRaw(Uint8List.fromList([0x0D]));
      return;
    }

    if (ctrlMode.value != CtrlMode.off && bytes.length == 1) {
      final code = bytes[0] & 0x1f;
      writeRaw(Uint8List.fromList([code]));
      if (ctrlMode.value == CtrlMode.oneshot) {
        ctrlMode.value = CtrlMode.off;
      }
      return;
    }
    writeRaw(Uint8List.fromList(bytes));
  }

  /// While reconnecting, a full-screen program reads plain keys as
  /// commands, so nothing typed blind is sent to one.
  void writeRaw(Uint8List data) {
    final provider = sshConnectionProvider(widget.sessionKey);
    final notifier = ref.read(provider.notifier);
    if (ref.read(provider).status == ConnectionStatus.reconnecting) {
      if (!_nativeController.isUsingAltBuffer) notifier.queueInput(data);
      return;
    }
    notifier.write(data);
  }

  final ValueNotifier<UploadProgress?> _uploadProgress = ValueNotifier(null);
  CancelToken? _uploadCancel;

  /// Picks local files and uploads them to the shell's scratch directory, its
  /// current directory or a folder the user picks, depending on
  /// [uploadDestinationSetting]. The remote paths are not typed in unless
  /// asked for - a menu at the cursor offers to paste them, so a stray upload
  /// never lands text mid-command. [uploadAutoPasteSetting] trades that away
  /// for the tap.
  ///
  /// The picker is a multi-select one, so this takes everything it returns.
  /// Uploading only the first and discarding the rest without saying so is
  /// the one behaviour that is not available here.
  Future<void> uploadFileToTerminal() async {
    final picked = [
      for (final file in await FilePicker.pickFiles())
        if (file.path case final path?) LocalUpload.file(file.name, path),
    ];
    if (picked.isEmpty) return;
    await _upload(picked, uploadDestinationSetting.value);
  }

  /// Only the agent knows where a live shell is ([_readAgentCwd]); without
  /// it, or before it reports, the current-directory destination asks the
  /// user instead of guessing. Overwrite prompts are all settled before
  /// anything is transferred, since a question raised mid-transfer would
  /// hide behind the progress bar and arrive too late for a file already
  /// being written - the scratch directory is timestamped instead, so
  /// nothing there can collide. Progress is one bar for the whole batch,
  /// cumulative across files, so an unknown size makes the total unknown
  /// rather than smaller.
  Future<void> _upload(
    List<LocalUpload> picked,
    UploadDestination destination,
  ) async {
    final session = _manager.getSession(widget.sessionKey.$1);
    if (session == null || !mounted) return;
    final t = Translations.of(context);

    final String directory;
    final cwd = destination == UploadDestination.currentDirectory
        ? await _readAgentCwd(session)
        : null;
    if (cwd != null) {
      directory = displayPathToSftp(cwd);
    } else if (destination != UploadDestination.tmp) {
      if (!mounted) return;
      final chosen = await _pickUploadFolder(session, picked);
      if (chosen == null) return;
      directory = chosen;
    } else {
      final client = await session.sftpClient;
      directory = await _resolveTmpDirectory(session, client);
    }
    if (!mounted) return;

    final planned = planUploadPaths(
      fileNames: picked.map((file) => file.name),
      directory: directory,
      timestamped: destination == UploadDestination.tmp,
    );

    final queue = <(LocalUpload, String)>[];
    final client = await session.sftpClient;
    final sftp = SftpService(client);
    final done = <String>[];
    try {
      for (var i = 0; i < picked.length; i++) {
        if (destination != UploadDestination.tmp &&
            await sftp.exists(planned[i])) {
          if (!mounted) return;
          if (await confirmUploadOverwrite(context, picked[i].name) != true) {
            continue;
          }
        }
        queue.add((picked[i], planned[i]));
      }
      if (queue.isEmpty || !mounted) return;

      final sizes = [for (final (file, _) in queue) await file.length()];
      final total = sizes.contains(null)
          ? null
          : sizes.fold<int>(0, (sum, size) => sum + size!);

      final cancel = CancelToken();
      _uploadCancel = cancel;
      _uploadProgress.value = UploadProgress(bytes: 0, total: total);
      var bytesBefore = 0;
      try {
        for (var i = 0; i < queue.length; i++) {
          cancel.throwIfCancelled();
          final (file, remotePath) = queue[i];
          _uploadProgress.value = UploadProgress(
            bytes: bytesBefore,
            total: total,
            index: i + 1,
            count: queue.length,
          );
          var fileSent = 0;
          await sftp.uploadStream(
            file.open(),
            remotePath,
            totalSize: sizes[i],
            cancel: cancel,
            onProgress: (sent, _) {
              fileSent = sent;
              _uploadProgress.value = UploadProgress(
                bytes: bytesBefore + sent,
                total: total,
                index: i + 1,
                count: queue.length,
              );
            },
          );
          bytesBefore += sizes[i] ?? fileSent;
          done.add(remotePath);
        }
      } catch (e) {
        if (!mounted) return;
        if (cancel.isCancelled || e is TransferCancelled) {
          AppNotifications.info(context, t.sftp.uploadCancelled);
        } else {
          AppNotifications.error(context, resolveSftpError(e, t));
        }
        return;
      } finally {
        _uploadCancel = null;
        _uploadProgress.value = null;
      }
    } finally {
      await sftp.close();
    }
    if (!mounted || done.isEmpty) return;

    final message = done.length == 1
        ? t.actionDock.uploaded(path: done.single)
        : t.actionDock.uploadedMany(count: done.length, path: directory);
    AppNotifications.success(context, message);
    final paste = uploadPasteText(
      done.map(sftpPathToDisplay),
      session.remoteShellType,
    );
    if (uploadAutoPasteSetting.value) {
      _paste(paste);
      return;
    }
    _showCursorMenu(
      (dismiss) => _PasteUploadPathMenu(
        onPaste: () {
          _paste(paste);
          dismiss();
        },
        onDismiss: dismiss,
      ),
    );
  }

  /// Folders picked for uploads this run, per machine, offered first.
  static final Map<String, List<String>> _recentUploadFolders = {};

  /// The same folder picker as copy and move, opened where the shell is when
  /// the agent knows that and in the SFTP home otherwise.
  Future<String?> _pickUploadFolder(
    ActiveSessionView session,
    List<LocalUpload> files,
  ) async {
    final t = Translations.of(context);
    final sftp = SftpService(await session.sftpClient);
    final cwd = await _readAgentCwd(session);
    var start = cwd == null ? '/' : displayPathToSftp(cwd);
    if (cwd == null) {
      try {
        await sftp.init();
        start = await sftp.sftp.absolute('.');
      } catch (_) {}
    }
    if (!mounted) {
      await sftp.close();
      return null;
    }
    final machine = session.profile.id;
    final chosen = await showSftpFolderPicker(
      context: context,
      sftp: sftp,
      title: files.length == 1
          ? t.actionDock.uploadNameTo(name: files.single.name)
          : t.actionDock.uploadItemsTo(count: files.length),
      actionLabel: t.actionDock.uploadHere,
      startPath: start,
      canChoose: (_) => true,
      canEnter: (_) => true,
      recent: _recentUploadFolders[machine] ?? const [],
      showHidden: sftpShowHiddenSetting.value,
    );
    await sftp.close();
    if (chosen == null) return null;
    final recent = _recentUploadFolders.putIfAbsent(machine, () => [])
      ..removeWhere((r) => sameSftpPath(r, chosen))
      ..insert(0, chosen);
    if (recent.length > 4) recent.removeRange(4, recent.length);
    return chosen;
  }

  /// Puts the shell's current directory on the clipboard.
  Future<void> copyCurrentPath() async {
    final session = _manager.getSession(widget.sessionKey.$1);
    if (session == null) return;
    final t = Translations.of(context);
    if (session.multiplexer != Multiplexer.termphin) {
      AppNotifications.error(context, t.actionDock.copyPathRequiresAgent);
      return;
    }
    final cwd = await _readAgentCwd(session);
    if (!mounted) return;
    if (cwd == null) {
      AppNotifications.error(context, t.actionDock.copyPathUnknown);
      return;
    }
    await copyToClipboard(context, cwd, message: t.sftp.pathCopied);
  }

  /// See [SftpBrowserView.terminalDirectory].
  Future<String?> _terminalDirectoryForSftp(ActiveSessionView session) async {
    if (!sftpFollowTerminalSetting.value) return null;
    final cwd = await _readAgentCwd(session);
    return cwd == null ? null : displayPathToSftp(cwd);
  }

  /// The directory the agent last saw the shell in - only meaningful for an
  /// agent-backed session, since a plain SSH one has nothing tracking it.
  /// Unix reads this straight off the agent's own state file, the same way
  /// the agent itself found it (`/proc/<pid>/cwd`). Windows has nothing
  /// external to read: PowerShell's `cd` doesn't update the OS-level
  /// process directory, so the value instead comes from the shell's own
  /// prompt reporting itself over an OSC marker - see
  /// `SshSessionManager._handleCwdMarker` and `session.reportedCwd`.
  Future<String?> _readAgentCwd(ActiveSessionView session) async {
    final muxName = session.muxName;
    if (session.multiplexer != Multiplexer.termphin || muxName == null) {
      return null;
    }
    final operatingSystem = _manager
        .agentStatusFor(session.profile.id)
        ?.operatingSystem;
    if (operatingSystem == 'Windows') {
      return session.reportedCwd;
    }
    try {
      final sftp = SftpService(await session.sftpClient);
      try {
        final text = await sftp.readSmallTextFile(
          '.cache/termphin/sessions/$muxName/cwd',
        );
        return text.isEmpty ? null : text;
      } finally {
        await sftp.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// The remote shell's own scratch directory, resolved rather than assumed:
  /// `/tmp` doesn't exist on Windows at all - OpenSSH's SFTP there is rooted
  /// at drive letters - so this asks the shell instead of hardcoding a Unix
  /// path. `$TMPDIR` (or `/tmp` when that's unset, which covers the ordinary
  /// case) over a Unix shell; `[System.IO.Path]::GetTempPath()` over
  /// PowerShell, the same call .NET itself uses to pick a temp folder, so it
  /// always resolves to something writable. Cached on the session: every
  /// upload after the first pays for none of this. SFTP on Windows roots
  /// paths at drive letters with a leading slash:
  /// `"C:\Users\...\Temp\"` becomes `"/C:/Users/.../Temp"`.
  Future<String> _resolveTmpDirectory(
    ActiveSessionView session,
    SSHClient client,
  ) async {
    final cached = session.resolvedTmpDirectory;
    if (cached != null) return cached;

    Future<String> resolve() async {
      switch (session.remoteShellType) {
        case RemoteShellType.powershell:
          try {
            final result = await client
                .run('[System.IO.Path]::GetTempPath()')
                .timeout(const Duration(seconds: 5));
            final raw = utf8.decode(result).trim();
            if (raw.isEmpty) return '/tmp';
            final posix = raw
                .replaceAll('\\', '/')
                .replaceAll(RegExp(r'/+$'), '');
            return posix.startsWith('/') ? posix : '/$posix';
          } catch (_) {
            return '/tmp';
          }
        case RemoteShellType.unix:
        case RemoteShellType.unknown:
          try {
            final result = await client
                .run(r'printf %s "${TMPDIR:-/tmp}"')
                .timeout(const Duration(seconds: 5));
            final raw = utf8.decode(result).trim();
            return raw.isEmpty ? '/tmp' : raw;
          } catch (_) {
            return '/tmp';
          }
      }
    }

    final resolved = await resolve();
    session.resolvedTmpDirectory = resolved;
    return resolved;
  }

  int? _sentCols;
  int? _sentRows;
  Timer? _resizeDebounce;

  /// How long the size has to hold still before the server hears about it.
  ///
  /// The pane is resized by the layout now, so it follows the keyboard frame by
  /// frame - and every frame of that animation is a window-change the remote
  /// shell acts on, which a full-screen TUI answers with a full repaint. The
  /// throttle belongs here, at the packet, rather than in the layout: the
  /// terminal is free to be the right size on every frame, the server is only
  /// told the size it settled on.
  static const _resizeSettleDelay = Duration(milliseconds: 120);

  void _onResize(int cols, int rows) {
    if (cols == _sentCols && rows == _sentRows) return;
    _sentCols = cols;
    _sentRows = rows;
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(_resizeSettleDelay, () {
      if (!mounted) return;
      ref
          .read(sshConnectionProvider(widget.sessionKey).notifier)
          .resize(cols, rows);
    });
  }

  void _clearSelection() {
    _nativeController.clearSelection();
    setState(() => _selectionPopupVisible = false);
  }

  /// The popup's position is measured inside the overlay entry's own
  /// builder, so the preview moves with the keyboard.
  void _handleLinkDetected(String url, double tapY) {
    _dismissLink();
    final overlay = Overlay.of(context);
    final globalTapY = _lastPointerGlobalY;

    _linkOverlayEntry = OverlayEntry(
      builder: (ctx) {
        const popupWidth = 280.0;
        const popupEstimatedHeight = 160.0;
        final screenSize = MediaQuery.sizeOf(ctx);
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismissLink,
                ),
              ),
              Positioned(
                top: linkPopupTop(
                  tapY: globalTapY,
                  screenHeight: screenSize.height,
                  keyboardInset: MediaQuery.viewInsetsOf(ctx).bottom,
                  popupHeight: popupEstimatedHeight,
                ),
                left: (screenSize.width - popupWidth) / 2,
                width: popupWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: LinkPreviewPopup(
                    key: ValueKey(url),
                    url: url,
                    tapY: tapY,
                    onDismiss: _dismissLink,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    overlay.insert(_linkOverlayEntry!);
  }

  void _dismissLink() {
    _linkOverlayEntry?.remove();
    _linkOverlayEntry = null;
  }

  void _dismissSelection() {
    _nativeController.doCopy();
    _clearSelection();
  }

  void openSearch() => _nativeController.openSearch();

  Future<void> handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text;
    if (text != null && text.isNotEmpty) _paste(text);
    _clearSelection();
  }

  void _paste(String text) {
    final payload = pastePayload(
      text,
      bracketed: _nativeController.bracketedPasteMode,
    );
    writeRaw(Uint8List.fromList(utf8.encode(payload)));
  }

  /// Asks for the permission the failed connection needed, and dials again the
  /// moment it is granted - the user has already said what they wanted by
  /// tapping this, so a second tap on Retry would only be ceremony. A refusal
  /// Android will not re-prompt for leaves its settings page as the way in.
  Future<void> _onAllowLocalNetwork() async {
    final permission = LocalNetworkPermission.instance;
    final result = await permission.request();
    if (!mounted) return;
    switch (result) {
      case LocalNetworkPermissionResult.granted:
        unawaited(
          ref.read(sshConnectionProvider(widget.sessionKey).notifier).connect(),
        );
      case LocalNetworkPermissionResult.permanentlyDenied:
        await permission.openAppSettings();
      case LocalNetworkPermissionResult.denied:
        break;
    }
  }

  Future<void> _onOpenLocalNetworkSettings() =>
      LocalNetworkPermission.instance.openAppSettings();

  Future<void> _handleShare() async {
    final text = await _nativeController.getSelectedText();
    if (!mounted) return;
    _clearSelection();
    if (text != null && text.isNotEmpty) {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null && box.hasSize
          ? (box.localToGlobal(Offset.zero) & box.size)
          : null;
      await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: origin),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sshConnectionProvider(widget.sessionKey));

    _terminalReady = _readyAttachId == state.attachId;

    if (state.status == ConnectionStatus.connecting ||
        state.status == ConnectionStatus.reconnecting) {
      final held = _heldFrame;
      if (state.status == ConnectionStatus.reconnecting &&
          held != null &&
          held.attachId == state.attachId) {
        return _buildTerminal(state, held.session, held.attachId);
      }
      return ConnectingView(
        profile: widget.sessionKey.$2,
        onCancel: widget.onClose,
        connectionLog: state.connectionLog,
        reconnectAttempt: state.reconnectAttempt,
        reconnectSecondsRemaining: state.reconnectSecondsRemaining,
        waitingForNetwork: state.waitingForNetwork,
      );
    }

    if (state.status == ConnectionStatus.error) {
      _heldFrame = null;
      final t = Translations.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
              decoration: BoxDecoration(
                color: context.colors.surfaceCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: context.colors.surfaceBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: context.colors.error.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      PhosphorIconsFill.warningCircle,
                      color: context.colors.error,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    t.terminal.connectFailed,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 7),
                    SelectableText(
                      connectionErrorText(
                        t,
                        state.failureReason,
                        widget.sessionKey.$2.authMethod,
                        fallback: state.errorMessage!,
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.colors.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (state.failureReason ==
                          SshFailureReason.localNetworkBlocked)
                        ElevatedButton.icon(
                          onPressed: _onAllowLocalNetwork,
                          icon: const Icon(
                            PhosphorIconsFill.houseLine,
                            size: 18,
                          ),
                          label: Text(t.connection.allowLocalNetwork),
                        ),
                      if (state.failureReason ==
                          SshFailureReason.localNetworkUnverified)
                        OutlinedButton.icon(
                          onPressed: _onOpenLocalNetworkSettings,
                          icon: const Icon(PhosphorIconsRegular.gear, size: 18),
                          label: Text(t.connection.openLocalNetworkSettings),
                        ),
                      _RetryButton(
                        primary:
                            state.failureReason !=
                            SshFailureReason.localNetworkBlocked,
                        label: t.common.retry,
                        onPressed: () => ref
                            .read(
                              sshConnectionProvider(widget.sessionKey).notifier,
                            )
                            .connect(),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onClose,
                        icon: const Icon(PhosphorIconsRegular.x, size: 18),
                        label: Text(t.common.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => openManual(
                      context,
                      connectionErrorManualPage(
                        state.failureReason,
                        widget.sessionKey.$2.authMethod,
                      ),
                    ),
                    icon: const Icon(PhosphorIconsRegular.question, size: 18),
                    label: Text(t.manual.howToFix),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (state.status == ConnectionStatus.connected) {
      if (!_terminalSettingsLoaded) {
        return const Center(child: CircularProgressIndicator());
      }

      final session = _manager.getSession(widget.sessionKey.$1);
      if (session == null) {
        return const Center(child: CircularProgressIndicator());
      }
      _ensureRebootRestoredListener(session);
      return _buildTerminal(state, session, state.attachId);
    }

    _heldFrame = null;
    return _buildOfflineView();
  }

  /// The terminal of [session], with [attachId] the pane that is live. While
  /// reconnecting that is the held frame, untouched but for the chip in the
  /// corner; after a reconnect the held frame stays over the new pane until
  /// the new one is ready. Panes are keyed children of one `Stack` so the
  /// held pane keeps its state when the new one is put under it.
  ///
  /// The special-keys toolbar rises above its resting spot to clear the
  /// keyboard, but this stack's own height doesn't shrink to match, so the
  /// selection popup carves the risen toolbar's strip out of its own bound,
  /// or it would end up drawn underneath it.
  ///
  /// The native view has to be in the tree to boot up and take the replayed
  /// scrollback, but showing it while it does means watching the history
  /// paint itself, so the connect screen is kept over it until it reports
  /// ready - or, after a reconnect, over the terminal it replaces. That
  /// outer stack stays even once it is ready: dropping it would put a
  /// `Column` where the `Stack` used to be, and Flutter would rebuild that
  /// whole subtree - including a fresh, empty platform view - instead of
  /// keeping the terminal that just replayed the history.
  ///
  /// The bubble over a selection is a finger's copy button; a desktop copies
  /// from the keys or a right click, so it never shows there.
  Widget _buildTerminal(
    SshConnectionState state,
    ActiveSessionView session,
    int attachId,
  ) {
    final reconnecting = state.status == ConnectionStatus.reconnecting;
    final held = _heldFrame;
    final replacing =
        !reconnecting &&
        !_terminalReady &&
        held != null &&
        held.attachId != attachId;
    if (!replacing && !reconnecting) {
      _heldFrame = (session: session, attachId: attachId);
    }
    final panes = [
      (session, attachId),
      if (replacing) (held.session, held.attachId),
    ];
    void openDetails() =>
        unawaited(showConnectionLogSheet(context, widget.sessionKey));

    final body = Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Offstage(
                offstage: widget.viewMode != SessionViewMode.terminal,
                child: Stack(
                  children: [
                    for (final (paneSession, paneAttachId) in panes)
                      _terminalPane(
                        paneSession,
                        paneAttachId,
                        live: paneAttachId == attachId,
                      ),
                    if (reconnecting)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: ReconnectingIndicator(
                          attempt: state.reconnectAttempt,
                          secondsRemaining: state.reconnectSecondsRemaining,
                          waitingForNetwork: state.waitingForNetwork,
                          queuedInput: state.queuedInput,
                          onTap: openDetails,
                        ),
                      )
                    else if (session.sshService case final service?)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: ConnectionQualityPill(
                          quality: service.quality,
                          onTap: openDetails,
                        ),
                      ),
                    if (_selectionPopupVisible &&
                        platformHas(PlatformFeature.touchControls))
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const popupHeight = 52.0;
                            const margin = 4.0;
                            final maxTop =
                                constraints.maxHeight -
                                popupHeight -
                                toolbarLiftFor(context);
                            var top = _selTopY > popupHeight
                                ? _selTopY - popupHeight
                                : _selBottomY + 8;
                            top = top.clamp(
                              margin,
                              maxTop < margin ? margin : maxTop,
                            );
                            return Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: EdgeInsets.only(top: top),
                                child: _CopyPastePopup(
                                  onCopy: _dismissSelection,
                                  onPaste: handlePaste,
                                  onShare: _handleShare,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (_cursorMenuAnchor != null && _cursorMenuContent != null)
                      CursorMenu(
                        anchor: _cursorMenuAnchor!,
                        onDismiss: _dismissCursorMenu,
                        child: _cursorMenuContent!,
                      ),
                    if (_suggestionsVisible)
                      CommandSuggestionPopup(
                        cursor: _suggestionRow!,
                        suggestions: _completion.suggestions.value,
                        keyboard: isDesktopPlatform,
                        selected: _suggestionPick,
                        onAccept: _acceptSuggestion,
                        onDismiss: _dismissSuggestions,
                      ),
                    if (_scrollModeManual && !_selectionPopupVisible)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: _ScrollToBottomButton(
                          onTap: () {
                            _nativeController.scrollToBottom();
                            setState(() => _scrollModeManual = false);
                          },
                          backgroundColor: Theme.of(
                            context,
                          ).scaffoldBackgroundColor,
                        ),
                      ),
                    UploadProgressBar(
                      progress: _uploadProgress,
                      onCancel: () => _uploadCancel?.cancel(),
                    ),
                  ],
                ),
              ),
              if (_sftpInitialized)
                Offstage(
                  offstage: widget.viewMode != SessionViewMode.sftp,
                  child: SftpBrowserView(
                    key: widget.sftpKey,
                    session: session,
                    terminalDirectory: () => _terminalDirectoryForSftp(session),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        if (!_terminalReady && !replacing)
          ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: ConnectingView(
              profile: widget.sessionKey.$2,
              onCancel: widget.onClose,
              connectionLog: state.connectionLog,
              restoringHistory: true,
            ),
          ),
      ],
    );
  }

  Widget _terminalPane(
    ActiveSessionView session,
    int attachId, {
    required bool live,
  }) {
    return Listener(
      key: ValueKey(attachId),
      onPointerDown: (e) {
        _lastPointerGlobalY = e.position.dy;
      },
      child: IgnorePointer(
        ignoring: !live,
        child: TerminalPane(
          outputStream: session.outputStream,
          inputStream: session.inputStream,
          inputReceipts: session.inputReceipts,
          onInput: _onInput,
          onResize: live ? _onResize : _ignoreResize,
          controller: live ? _nativeController : null,
          initialHistory: session.pendingReplay,
          onReady: () => _onTerminalReady(attachId),
          onFontSizeChanged: _onFontSizeChanged,
          onSelectionStateChanged: (active, topY, bottomY) {
            setState(() {
              _selectionPopupVisible = active;
              _selTopY = topY;
              _selBottomY = bottomY;
            });
          },
          onScrollModeChanged: (isManual) {
            if (mounted) {
              setState(() => _scrollModeManual = isManual);
            }
          },
          onLinkDetected: _handleLinkDetected,
          onKeyEvent: _onTerminalKey,
        ),
      ),
    );
  }

  static void _ignoreResize(int cols, int rows) {}

  /// Shown for tabs restored from disk: the remote session is still on the
  /// server, so a single tap picks the shell back up.
  Widget _buildOfflineView() {
    final t = Translations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
            decoration: BoxDecoration(
              color: context.colors.surfaceCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: context.colors.surfaceBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    PhosphorIconsFill.plugs,
                    color: context.colors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  t.session.offlineTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  t.session.offlineBody,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.colors.textTertiary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => ref
                      .read(sshConnectionProvider(widget.sessionKey).notifier)
                      .connect(),
                  icon: const Icon(PhosphorIconsFill.plugsConnected, size: 18),
                  label: Text(t.session.attach),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CopyPastePopup extends StatelessWidget {
  const _CopyPastePopup({
    required this.onCopy,
    required this.onPaste,
    required this.onShare,
  });

  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final surface = Theme.of(context).colorScheme.surface;
    final border = Theme.of(context).dividerColor;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PopupBtn(
              label: t.common.copy,
              icon: PhosphorIconsFill.copy,
              onTap: onCopy,
            ),
            VerticalDivider(width: 1, thickness: 1, color: border),
            _PopupBtn(
              label: t.terminal.paste,
              icon: PhosphorIconsFill.clipboardText,
              onTap: onPaste,
            ),
            VerticalDivider(width: 1, thickness: 1, color: border),
            _PopupBtn(
              label: t.common.share,
              icon: PhosphorIconsFill.shareFat,
              onTap: onShare,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown at the cursor after a fast upload finishes - offers to type the
/// remote path in rather than doing it unasked, so a finished upload never
/// drops text mid-command. Styled to match [_CopyPastePopup].
class _PasteUploadPathMenu extends StatelessWidget {
  const _PasteUploadPathMenu({required this.onPaste, required this.onDismiss});

  final VoidCallback onPaste;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final surface = Theme.of(context).colorScheme.surface;
    final border = Theme.of(context).dividerColor;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PopupBtn(
              label: t.actionDock.pasteUploadedPath,
              icon: PhosphorIconsFill.clipboardText,
              onTap: onPaste,
            ),
            VerticalDivider(width: 1, thickness: 1, color: border),
            _PopupIconBtn(icon: PhosphorIconsRegular.x, onTap: onDismiss),
          ],
        ),
      ),
    );
  }
}

class _PopupIconBtn extends StatelessWidget {
  const _PopupIconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Theme.of(context).colorScheme.surface.invisible,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 16, color: textColor),
        ),
      ),
    );
  }
}

class _PopupBtn extends StatelessWidget {
  const _PopupBtn({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Theme.of(context).colorScheme.surface.invisible,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({
    required this.onTap,
    required this.backgroundColor,
  });

  final VoidCallback onTap;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).dividerColor;
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: Translations.of(context).terminal.scrollToBottom,
      child: Material(
        color: backgroundColor.invisible,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: backgroundColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              PhosphorIconsFill.arrowLineDown,
              size: 20,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Retry, drawn filled or outlined depending on whether it is the thing to do
/// next. A failure the user can clear - a missing permission - puts its own fix
/// first, and two filled buttons side by side would say neither is.
class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.primary,
    required this.label,
    required this.onPressed,
  });

  final bool primary;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const icon = Icon(PhosphorIconsFill.arrowClockwise, size: 18);
    final text = Text(label);
    return primary
        ? ElevatedButton.icon(onPressed: onPressed, icon: icon, label: text)
        : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: text);
  }
}
