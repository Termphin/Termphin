import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/platform/share_intent_service.dart';
import '../../services/settings/sftp_settings.dart';
import '../../services/sftp/cancel_token.dart';
import '../../services/sftp/sftp_service.dart';
import '../../services/sftp/upload_plan.dart';
import '../../services/ssh/ssh_prompts.dart';
import '../../services/ssh/ssh_service.dart';
import '../../theme/theme.dart';
import '../../utils/connection_error_text.dart';
import '../../utils/format_size.dart';
import '../../utils/sftp_error_handler.dart';
import '../../utils/sftp_path.dart';
import '../../widgets/sftp/confirm_overwrite.dart';
import '../../widgets/sftp/sftp_folder_picker.dart';
import '../../widgets/sftp/upload_progress.dart';
import '../../widgets/ssh/host_key_dialog.dart';
import '../../widgets/ssh/keyboard_interactive_dialog.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/empty_state.dart';

enum _Stage { connecting, failed, picking, uploading, done }

/// One question on screen at a time, as in the app.
final _prompts = ConnectionPromptQueue();

/// Connects to [profile] for nothing but SFTP - no shell, no session, no tab
/// - and asks for a folder, starting in the home folder. Choosing one uploads
/// [content] there and pops with true once it is all on the server.
///
/// Popping any earlier pops with nothing and hangs up, so the machine list
/// under this can be tried again with another machine.
class ShareUploadScreen extends ConsumerStatefulWidget {
  const ShareUploadScreen({
    super.key,
    required this.profile,
    required this.content,
    this.newService,
    this.openSftp,
    this.closeDelay = const Duration(milliseconds: 900),
  });

  final SshProfile profile;
  final SharedContent content;

  /// Stand-ins for the transport, for tests.
  final SshService Function()? newService;
  final SftpService Function(SSHClient client)? openSftp;

  /// How long "Uploaded" stays up before the screen closes.
  final Duration closeDelay;

  @override
  ConsumerState<ShareUploadScreen> createState() => _ShareUploadScreenState();
}

/// A back press while files are going up stops them instead of leaving, and
/// the folder picker stays underneath the upload progress, so a failed
/// upload comes back to the folder it was going to.
class _ShareUploadScreenState extends ConsumerState<ShareUploadScreen> {
  var _stage = _Stage.connecting;
  SshService? _ssh;
  SftpService? _sftp;
  String? _home;
  String? _error;
  UploadProgress? _progress;
  String? _current;
  String? _landed;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    final sftp = _sftp;
    final ssh = _ssh;
    unawaited(() async {
      await sftp?.close();
      await ssh?.disconnect();
    }());
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _stage = _Stage.connecting;
      _error = null;
    });
    final service = (widget.newService ?? SshService.new)();
    _ssh = service;
    SftpService? sftp;
    try {
      await service.connect(
        widget.profile,
        onHostKeyPrompt: _prompts.hostKey(showHostKeyPrompt),
        onKeyboardInteractive: _prompts.keyboardInteractive(
          showKeyboardInteractivePrompt,
        ),
      );
      sftp = (widget.openSftp ?? SftpService.new)(service.client!);
      await sftp.init();
      final home = await sftp.sftp.absolute('.');
      if (!mounted) {
        await sftp.close();
        return;
      }
      setState(() {
        _sftp = sftp;
        _home = home;
        _stage = _Stage.picking;
      });
    } catch (error) {
      await sftp?.close();
      await service.disconnect();
      if (!mounted || _ssh != service) return;
      _ssh = null;
      final t = Translations.of(context);
      setState(() {
        _stage = _Stage.failed;
        _error = error is SshConnectException
            ? connectionErrorText(
                t,
                error.reason,
                widget.profile.authMethod,
                fallback: error.message,
              )
            : resolveSftpError(error, t);
      });
    }
  }

  /// Overwrites are asked about before anything moves, as in the terminal's
  /// upload: a question from behind the progress screen would come too late
  /// for a file already being written. One file of unknown size makes the
  /// batch's total unknown too, not smaller.
  Future<void> _upload(String directory) async {
    final sftp = _sftp;
    if (sftp == null || _stage != _Stage.picking) return;
    final t = Translations.of(context);
    final files = widget.content.files;
    final planned = planUploadPaths(
      fileNames: files.map((file) => file.name),
      directory: directory,
      timestamped: false,
    );

    final queue = <(LocalUpload, String)>[];
    try {
      for (var i = 0; i < files.length; i++) {
        if (await sftp.exists(planned[i])) {
          if (!mounted) return;
          if (await confirmUploadOverwrite(context, files[i].name) != true) {
            continue;
          }
        }
        queue.add((files[i], planned[i]));
      }
    } catch (error) {
      if (mounted) AppNotifications.error(context, resolveSftpError(error, t));
      return;
    }
    if (queue.isEmpty || !mounted) return;

    final sizes = [for (final (file, _) in queue) await file.length()];
    final total = sizes.contains(null)
        ? null
        : sizes.fold<int>(0, (sum, size) => sum + size!);
    final cancel = CancelToken();
    _cancel = cancel;
    setState(() {
      _stage = _Stage.uploading;
      _progress = UploadProgress(bytes: 0, total: total);
    });

    var bytesBefore = 0;
    try {
      for (var i = 0; i < queue.length; i++) {
        cancel.throwIfCancelled();
        final (file, remotePath) = queue[i];
        setState(() => _current = file.name);
        var fileSent = 0;
        await sftp.uploadStream(
          file.open(),
          remotePath,
          totalSize: sizes[i],
          cancel: cancel,
          onProgress: (sent, _) {
            fileSent = sent;
            if (!mounted) return;
            setState(
              () => _progress = UploadProgress(
                bytes: bytesBefore + sent,
                total: total,
                index: i + 1,
                count: queue.length,
              ),
            );
          },
        );
        bytesBefore += sizes[i] ?? fileSent;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _stage = _Stage.picking);
      if (cancel.isCancelled || error is TransferCancelled) {
        AppNotifications.info(context, t.sftp.uploadCancelled);
      } else {
        AppNotifications.error(context, resolveSftpError(error, t));
      }
      return;
    } finally {
      _cancel = null;
    }
    if (!mounted) return;

    setState(() {
      _stage = _Stage.done;
      _landed = queue.length == 1 ? queue.single.$2 : directory;
    });
    await Future<void>.delayed(widget.closeDelay);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final anonymize = ref.watch(anonymizeProvider);
    final machine = anonymize
        ? IdentityAnonymizer.name(widget.profile.id)
        : widget.profile.name;

    return PopScope(
      canPop: _stage != _Stage.uploading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel?.cancel();
      },
      child: switch (_stage) {
        _Stage.connecting => Scaffold(
          appBar: AppBar(title: Text(machine)),
          body: _Status(
            leading: const CircularProgressIndicator(),
            title: t.share.connecting(name: machine),
          ),
        ),
        _Stage.failed => Scaffold(
          appBar: AppBar(title: Text(machine)),
          body: SafeArea(
            top: false,
            child: EmptyStatePanel(
              icon: PhosphorIconsRegular.warningCircle,
              title: t.share.connectFailed,
              subtitle: _error,
              action: FilledButton(
                onPressed: () => unawaited(_connect()),
                child: Text(t.common.retry),
              ),
            ),
          ),
        ),
        _ => Stack(
          children: [
            SftpFolderPicker(
              sftp: _sftp!,
              title: widget.content.files.length == 1
                  ? t.actionDock.uploadNameTo(
                      name: widget.content.files.single.name,
                    )
                  : t.actionDock.uploadItemsTo(
                      count: widget.content.files.length,
                    ),
              actionLabel: t.actionDock.uploadHere,
              startPath: _home!,
              canChoose: (_) => true,
              canEnter: (_) => true,
              showHidden: sftpShowHiddenSetting.value,
              onChoose: (folder) => unawaited(_upload(folder)),
            ),
            if (_stage == _Stage.uploading)
              Positioned.fill(child: _uploading(t))
            else if (_stage == _Stage.done)
              Positioned.fill(child: _done(t)),
          ],
        ),
      },
    );
  }

  /// The progress bar is clipped like the browser's own transfer dialog:
  /// the theme's default track is a tint of the fill, too close to tell
  /// apart otherwise.
  Widget _uploading(Translations t) {
    final colors = context.colors;
    final progress = _progress;
    final total = progress?.total;
    return Scaffold(
      body: _Status(
        leading: Icon(
          PhosphorIconsRegular.cloudArrowUp,
          size: AppTheme.icon40,
          color: colors.primary,
        ),
        title: t.share.uploading,
        children: [
          if (_current case final name?)
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: colors.uiStyle.copyWith(color: colors.textSecondary),
            ),
          if (progress != null && progress.isBatch)
            Text(
              t.share.fileOf(
                index: progress.index ?? 1,
                count: progress.count ?? 1,
              ),
              style: colors.uiSmall.copyWith(color: colors.textTertiary),
            ),
          const SizedBox(height: AppTheme.space20),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: LinearProgressIndicator(
              value: progress?.fraction,
              minHeight: 6,
              backgroundColor: colors.surfaceOffset,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            total == null
                ? formatFileSize(progress?.bytes ?? 0)
                : '${formatFileSize(progress?.bytes ?? 0)} / '
                      '${formatFileSize(total)}',
            style: colors.uiSmall.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppTheme.space20),
          TextButton(
            onPressed: () => _cancel?.cancel(),
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );
  }

  Widget _done(Translations t) {
    final colors = context.colors;
    return Scaffold(
      body: _Status(
        leading: Icon(
          PhosphorIconsRegular.checkCircle,
          size: AppTheme.icon48,
          color: colors.success,
        ),
        title: t.share.done,
        children: [
          if (_landed case final path?)
            Text(
              sftpPathToDisplay(path),
              textAlign: TextAlign.center,
              style: colors.monoSmall.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// Something under way, in the middle of the screen.
class _Status extends StatelessWidget {
  const _Status({
    required this.leading,
    required this.title,
    this.children = const [],
  });

  final Widget leading;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(height: AppTheme.space20),
              Text(title, textAlign: TextAlign.center, style: colors.itemTitle),
              const SizedBox(height: AppTheme.space6),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
