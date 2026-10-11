import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../../utils/format_size.dart';

/// Bytes sent so far, and the total when the local file's size was known
/// upfront (it always is - the only null case is nothing in flight yet).
class UploadProgress {
  const UploadProgress({
    required this.bytes,
    this.total,
    this.index,
    this.count,
  });

  final int bytes;
  final int? total;

  /// Which file of the batch is in flight, 1-based, and how many there are.
  /// Null for a single-file upload, where a counter would say nothing.
  final int? index;
  final int? count;

  bool get isBatch => (count ?? 1) > 1;

  double? get fraction =>
      total == null || total! <= 0 ? null : (bytes / total!).clamp(0.0, 1.0);
}

/// Bar pinned under the tab strip for the duration of a fast upload - size,
/// speed and a cancel button all live inside it. Top of the session view
/// rather than above the special-keys toolbar: that spot rises with the
/// keyboard and has no room to spare for a bar this thick, right where the
/// toolbar itself is trying to float.
class UploadProgressBar extends StatefulWidget {
  const UploadProgressBar({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  /// Null hides the bar; otherwise the bytes sent (and total, if known).
  final ValueListenable<UploadProgress?> progress;
  final VoidCallback onCancel;

  @override
  State<UploadProgressBar> createState() => _UploadProgressBarState();
}

/// The counter leads: with several files in flight the bytes alone say
/// nothing about how much of the batch is left.
class _UploadProgressBarState extends State<UploadProgressBar> {
  static const _height = 36.0;

  /// Recent (time, bytes) samples, kept to a short window so the reported
  /// speed follows the connection instead of averaging the whole upload.
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
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: ValueListenableBuilder<UploadProgress?>(
        valueListenable: widget.progress,
        builder: (context, value, _) {
          if (value == null) {
            _samples.clear();
            return const SizedBox.shrink();
          }
          final rate = _rate(value.bytes);
          final size = value.total != null
              ? t.sftp.transferBytes(
                  done: formatFileSize(value.bytes),
                  total: formatFileSize(value.total),
                )
              : formatFileSize(value.bytes);
          final counter = value.isBatch
              ? '${t.actionDock.uploadingFile(index: value.index!, count: value.count!)} · '
              : '';
          final label = rate == null
              ? '$counter$size'
              : '$counter$size · '
                    '${t.sftp.transferRate(rate: formatFileSize(rate.round()))}';

          return Material(
            color: context.colors.surfaceOffset,
            child: SizedBox(
              height: _height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value.fraction ?? 0.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: t.common.cancel,
                        child: InkWell(
                          onTap: widget.onCancel,
                          child: SizedBox(
                            width: _height,
                            height: _height,
                            child: Icon(
                              PhosphorIconsRegular.x,
                              size: 16,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
