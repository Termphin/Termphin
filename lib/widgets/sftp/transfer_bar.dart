import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/sftp/download_service.dart';
import '../../services/sftp/transfer_queue.dart';
import '../../theme/theme.dart';
import '../../utils/format_size.dart';
import '../../utils/sftp_error_handler.dart';
import 'transfer_rate.dart';

/// The session's transfers, pinned under the tab strip over both the terminal
/// and the file browser.
///
/// Collapsed it is one thin strip that fills like a progress bar; tapping it
/// drops the full list over the content below. The list is laid over rather
/// than pushing anything down: resizing the terminal would send the server a
/// new window size and reflow the screen every time it opened.
///
/// Meant for a [Stack] that covers the session: it takes only the room it
/// draws in, so taps elsewhere fall through while it is collapsed.
class TransferBar extends StatefulWidget {
  const TransferBar({super.key, required this.queue, required this.expanded});

  static const height = 36.0;

  final TransferQueue queue;

  /// Owned by the session so the back button can fold the list away.
  final ValueNotifier<bool> expanded;

  @override
  State<TransferBar> createState() => _TransferBarState();
}

/// Two animations: [_shown] slides the strip in from under the tab strip and
/// back out, [_open] drops the list and dims what is behind it. Both run
/// their exit with the last frame that had something to show, since by then
/// the queue itself may already be empty.
class _TransferBarState extends State<TransferBar>
    with TickerProviderStateMixin {
  final _meter = TransferRateMeter();
  int? _meteredJob;

  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: AppTheme.motionSlow,
  );
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: AppTheme.motionSlow,
  );
  late final Animation<double> _shownCurve = CurvedAnimation(
    parent: _shown,
    curve: AppTheme.interactiveCurve,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<double> _openCurve = CurvedAnimation(
    parent: _open,
    curve: AppTheme.interactiveCurve,
    reverseCurve: Curves.easeInCubic,
  );

  Widget? _lastStrip;
  Widget? _lastPanel;

  /// The rate of [job], fed from the one meter: only the running job moves,
  /// so a new job starts the meter over.
  double? _rate(TransferJob job) {
    if (_meteredJob != job.id) {
      _meter.reset();
      _meteredJob = job.id;
    }
    return _meter.sample(job.progress.bytes);
  }

  @override
  void initState() {
    super.initState();
    widget.queue.addListener(_onQueueChanged);
    widget.expanded.addListener(_onExpandedChanged);
    _shown.value = widget.queue.jobs.isEmpty ? 0 : 1;
    _open.value = widget.expanded.value ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant TransferBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queue != widget.queue) {
      oldWidget.queue.removeListener(_onQueueChanged);
      widget.queue.addListener(_onQueueChanged);
    }
    if (oldWidget.expanded != widget.expanded) {
      oldWidget.expanded.removeListener(_onExpandedChanged);
      widget.expanded.addListener(_onExpandedChanged);
    }
  }

  @override
  void dispose() {
    widget.queue.removeListener(_onQueueChanged);
    widget.expanded.removeListener(_onExpandedChanged);
    _shown.dispose();
    _open.dispose();
    super.dispose();
  }

  bool get _instant => MediaQuery.disableAnimationsOf(context);

  void _run(AnimationController controller, bool forward) {
    if (_instant) {
      controller.value = forward ? 1 : 0;
    } else if (forward) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  /// An emptied queue folds the list away, so the next transfer does not
  /// open on top of the content.
  void _onQueueChanged() {
    final empty = widget.queue.jobs.isEmpty;
    if (empty) widget.expanded.value = false;
    _run(_shown, !empty);
  }

  void _onExpandedChanged() => _run(_open, widget.expanded.value);

  void _toggle() => widget.expanded.value = !widget.expanded.value;

  void _collapse() => widget.expanded.value = false;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.queue, widget.expanded]),
      builder: (context, _) {
        final queue = widget.queue;
        if (queue.jobs.isNotEmpty) {
          final running = queue.running;
          final rate = running == null ? null : _rate(running);
          _lastStrip = _Strip(
            queue: queue,
            rate: rate,
            expanded: widget.expanded.value,
            onTap: _toggle,
          );
          _lastPanel = _Panel(queue: queue, rate: rate, maxHeight: maxHeight);
        }
        return AnimatedBuilder(
          animation: Listenable.merge([_shown, _open]),
          builder: (context, _) {
            if (_shown.isDismissed || _lastStrip == null) {
              return const SizedBox.shrink();
            }
            final dimming = _open.value > 0;
            return Stack(
              children: [
                if (dimming)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !widget.expanded.value,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _collapse,
                        child: FadeTransition(
                          opacity: _openCurve,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ClipRect(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizeTransition(
                          sizeFactor: _shownCurve,
                          alignment: Alignment.bottomCenter,
                          child: _lastStrip,
                        ),
                        if (dimming)
                          SizeTransition(
                            sizeFactor: _openCurve,
                            alignment: Alignment.bottomCenter,
                            child: FadeTransition(
                              opacity: _openCurve,
                              child: _lastPanel,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

IconData _kindIcon(TransferJobKind kind) => switch (kind) {
  TransferJobKind.upload => PhosphorIconsRegular.uploadSimple,
  TransferJobKind.download => PhosphorIconsRegular.downloadSimple,
  TransferJobKind.copy => PhosphorIconsRegular.copy,
  TransferJobKind.move => PhosphorIconsRegular.arrowsLeftRight,
};

/// Bytes and speed while a job moves; the job's own place in the queue
/// otherwise.
String _statusLine(Translations t, TransferJob job, double? rate) {
  if (job.isCancelling) return t.sftp.queue.cancelling;
  if (job.state == TransferJobState.queued) return t.sftp.queue.waiting;
  if (job.state == TransferJobState.failed) {
    return resolveSftpError(job.error ?? '', t);
  }
  if (job.kind == TransferJobKind.copy) return t.sftp.queue.copying;
  if (job.kind == TransferJobKind.move) return t.sftp.queue.moving;
  final progress = job.progress;
  if (progress.phase == TransferPhase.scanning) {
    return t.sftp.transferScanning(count: progress.itemIndex);
  }
  final total = progress.totalBytes;
  return [
    if (progress.itemCount > 1)
      t.sftp.transferItemCount(
        current: progress.itemIndex,
        total: progress.itemCount,
      ),
    total != null
        ? t.sftp.transferBytes(
            done: formatFileSize(progress.bytes),
            total: formatFileSize(total),
          )
        : formatFileSize(progress.bytes),
    if (rate != null) t.sftp.transferRate(rate: formatFileSize(rate.round())),
  ].join(' · ');
}

/// The collapsed bar, drawn as fast upload always drew it: a thin strip that
/// fills, its text centred, a caret where the cancel button was. Once only
/// failures are left it fills with the error colour and says how many.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.queue,
    required this.rate,
    required this.expanded,
    required this.onTap,
  });

  final TransferQueue queue;
  final double? rate;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final running = queue.running;

    final String label;
    final double fraction;
    final Color fill;
    if (running != null) {
      label = [
        if (queue.runSize > 1)
          t.sftp.queue.position(
            position: queue.runPosition,
            count: queue.runSize,
          ),
        _statusLine(t, running, rate),
      ].join(' · ');
      fraction = queue.overallFraction ?? 0.0;
      fill = colors.primary;
    } else {
      label = t.sftp.queue.failedCount(
        count: queue.jobs
            .where((job) => job.state == TransferJobState.failed)
            .length,
      );
      fraction = 1.0;
      fill = colors.error;
    }

    return Semantics(
      button: true,
      label: expanded ? t.sftp.queue.hide : t.sftp.queue.show,
      child: Material(
        color: colors.surfaceOffset,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: TransferBar.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: fraction),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : AppTheme.motionSlow,
                    curve: Curves.easeOut,
                    builder: (context, value, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: fill.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const SizedBox(width: TransferBar.height),
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: TransferBar.height,
                      height: TransferBar.height,
                      child: Icon(
                        expanded
                            ? PhosphorIconsRegular.caretUp
                            : PhosphorIconsRegular.caretDown,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every job of the session, oldest first, in a card drawn like the app's
/// `⋮` menus.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.queue,
    required this.rate,
    required this.maxHeight,
  });

  final TransferQueue queue;
  final double? rate;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final jobs = queue.jobs;
    final anyFailed = jobs.any((job) => job.state == TransferJobState.failed);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppTheme.motionSlow,
        curve: AppTheme.interactiveCurve,
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: colors.surfaceBorderStrong),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    for (final job in jobs)
                      _JobRow(
                        key: ValueKey(job.id),
                        job: job,
                        rate: job == queue.running ? rate : null,
                        onCancel: () => queue.cancel(job),
                      ),
                    if (anyFailed && !queue.isBusy)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TextButton(
                            onPressed: queue.clearFinished,
                            child: Text(t.sftp.queue.clearFinished),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    super.key,
    required this.job,
    required this.rate,
    required this.onCancel,
  });

  final TransferJob job;
  final double? rate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final failed = job.state == TransferJobState.failed;
    final running = job.state == TransferJobState.running;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      child: Row(
        children: [
          Icon(
            _kindIcon(job.kind),
            size: 18,
            color: failed
                ? colors.error
                : running
                ? colors.primary
                : colors.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.progress.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: colors.uiStyle.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusLine(t, job, rate),
                  maxLines: failed ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: colors.uiSmall.copyWith(
                    color: failed ? colors.error : colors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (job.canCancel)
            IconButton(
              tooltip: t.common.cancel,
              onPressed: onCancel,
              icon: Icon(
                PhosphorIconsRegular.x,
                size: 16,
                color: colors.textSecondary,
              ),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}
