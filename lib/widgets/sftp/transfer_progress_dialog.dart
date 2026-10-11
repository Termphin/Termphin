import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/sftp/cancel_token.dart';
import '../../services/sftp/download_service.dart';
import '../../theme/theme.dart';
import '../../utils/format_size.dart';

enum TransferKind { download, upload }

/// One transfer and the dialog showing it.
///
/// The dialog is closed by removing its own route rather than popping whatever
/// happens to be on top, so a transfer that finishes while another sheet is
/// open cannot take that sheet down with it. Cancelling closes the dialog at
/// once and trips [cancel]; the transfer itself unwinds in the background and
/// throws [TransferCancelled], which callers report as a cancellation rather
/// than an error.
class TransferSession {
  TransferSession({required this.kind, required String initialLabel})
    : progress = ValueNotifier(TransferProgress(label: initialLabel));

  final TransferKind kind;
  final CancelToken cancel = CancelToken();
  final ValueNotifier<TransferProgress> progress;

  NavigatorState? _navigator;
  Route<void>? _route;
  var _closed = false;

  bool get isCancelled => cancel.isCancelled;

  void show(BuildContext context) {
    _navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        _route = ModalRoute.of(dialogContext) as Route<void>?;
        return _TransferProgressDialog(session: this);
      },
    );
  }

  void update(TransferProgress value) {
    if (_closed) return;
    progress.value = value;
  }

  /// Trips the token and takes the dialog down immediately - waiting for the
  /// transfer to notice would leave a dead dialog on screen for as long as the
  /// network takes to answer.
  void cancelTransfer() {
    cancel.cancel();
    close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final route = _route;
    if (route != null && route.isActive) {
      _navigator?.removeRoute(route);
    }
    _route = null;
    _navigator = null;
    progress.dispose();
  }
}

class _TransferProgressDialog extends StatefulWidget {
  const _TransferProgressDialog({required this.session});

  final TransferSession session;

  @override
  State<_TransferProgressDialog> createState() =>
      _TransferProgressDialogState();
}

/// The back button is the other way people say stop; treating it as Cancel
/// beats trapping them in a dialog they cannot dismiss.
class _TransferProgressDialogState extends State<_TransferProgressDialog> {
  /// Recent (time, bytes) samples, kept to a short window so the rate follows
  /// the connection instead of averaging the whole transfer.
  final List<(DateTime, int)> _samples = [];

  static const _rateWindow = Duration(seconds: 3);

  double? _rate(int bytes) {
    final now = DateTime.now();
    if (_samples.isEmpty || _samples.last.$2 != bytes) {
      _samples.add((now, bytes));
    }
    _samples.removeWhere((sample) => now.difference(sample.$1) > _rateWindow);
    if (_samples.length < 2) return null;
    final seconds =
        _samples.last.$1.difference(_samples.first.$1).inMilliseconds / 1000;
    if (seconds <= 0) return null;
    final delta = _samples.last.$2 - _samples.first.$2;
    return delta <= 0 ? null : delta / seconds;
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final isDownload = widget.session.kind == TransferKind.download;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.session.cancelTransfer();
      },
      child: AlertDialog(
        backgroundColor: context.colors.surfaceElevated,
        surfaceTintColor: context.colors.surfaceElevated.invisible,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          side: BorderSide(color: context.colors.surfaceBorder),
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        content: ValueListenableBuilder<TransferProgress>(
          valueListenable: widget.session.progress,
          builder: (context, value, _) {
            final fraction = value.fraction;
            final rate = _rate(value.bytes);
            return SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isDownload
                            ? PhosphorIconsFill.downloadSimple
                            : PhosphorIconsFill.uploadSimple,
                        size: 18,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isDownload
                              ? t.sftp.downloadingTitle
                              : t.sftp.uploadingTitle,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (fraction != null)
                        Text(
                          '${(fraction * 100).round()}%',
                          style: TextStyle(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    value.phase == TransferPhase.scanning
                        ? t.sftp.transferScanning(count: value.itemIndex)
                        : value.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 6,
                      backgroundColor: context.colors.surfaceOffset,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        context.colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _sizeLine(t, value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (rate != null)
                        Text(
                          t.sftp.transferRate(
                            rate: formatFileSize(rate.round()),
                          ),
                          style: TextStyle(
                            color: context.colors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        actions: [
          TextButton(
            onPressed: widget.session.cancelTransfer,
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
            ),
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );
  }

  /// "4.2 MB of 18 MB", falling back to what has arrived when no size was
  /// announced, and to the item counter for a multi-file transfer.
  String _sizeLine(Translations t, TransferProgress value) {
    if (value.phase == TransferPhase.scanning) return '';
    final total = value.totalBytes;
    final size = total != null
        ? t.sftp.transferBytes(
            done: formatFileSize(value.bytes),
            total: formatFileSize(total),
          )
        : formatFileSize(value.bytes);
    if (value.itemCount <= 1) return size;
    final counter = t.sftp.transferItemCount(
      current: value.itemIndex,
      total: value.itemCount,
    );
    return '$counter · $size';
  }
}
