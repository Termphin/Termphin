import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../services/platform/linux_self_updater.dart';
import '../../theme/theme.dart';

/// Modal progress dialog shown while downloading and verifying a Linux AppImage
/// update.
class UpdateDownloadDialog extends StatelessWidget {
  const UpdateDownloadDialog({
    super.key,
    required this.version,
    required this.progress,
    required this.onCancel,
  });

  final String version;
  final ValueListenable<LinuxUpdateProgress> progress;
  final VoidCallback onCancel;

  String _formatMb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;

    return PopScope(
      canPop: false,
      child: ValueListenableBuilder<LinuxUpdateProgress>(
        valueListenable: progress,
        builder: (ctx, snap, _) {
          final isVerifying = snap.stage == LinuxUpdateStage.verifying;
          final fraction = snap.fraction;
          final total = snap.total;
          final statusText = isVerifying
              ? t.updates.verifying
              : t.updates.downloading(version: version);
          final detailText = total != null && total > 0
              ? t.updates.progressBytes(
                  received: _formatMb(snap.received),
                  total: _formatMb(total),
                  percent: ((snap.received / total).clamp(0.0, 1.0) * 100)
                      .round(),
                )
              : t.updates.progressUnknown(received: _formatMb(snap.received));

          return AlertDialog(
            title: Text(t.updates.downloadingTitle),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: AppTheme.font14,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: AppTheme.space6,
                      color: colors.primary,
                      backgroundColor: colors.surfaceOffset,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space8),
                  Text(
                    detailText,
                    style: TextStyle(
                      fontSize: AppTheme.font12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isVerifying ? null : onCancel,
                child: Text(t.common.cancel),
              ),
            ],
          );
        },
      ),
    );
  }
}
