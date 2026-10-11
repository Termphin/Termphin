import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Scrollable, read-only output of one snippet run.
///
/// The text comes from the run record rather than a live session: a run's
/// session is torn down the moment it reports, so this has to keep reading
/// afterwards. Plain text rather than a terminal - nothing here is typed
/// into, and a text view costs none of the machinery a real terminal needs,
/// which matters when a batch puts one of these on screen per machine.
class SnippetRunOutput extends StatefulWidget {
  const SnippetRunOutput({
    super.key,
    required this.text,
    this.follow = true,
    this.height = 148,
  });

  final String text;

  /// Whether new output should scroll itself into view. False once the run
  /// has finished, so reading back an old one starts where it was left.
  final bool follow;
  final double height;

  @override
  State<SnippetRunOutput> createState() => _SnippetRunOutputState();
}

class _SnippetRunOutputState extends State<SnippetRunOutput> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant SnippetRunOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.follow && widget.text != oldWidget.text) _stickToBottom();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Follows the output only while the user has not scrolled away from it.
  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels > position.maxScrollExtent - 60) {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: context.colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: context.colors.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: SelectionArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              widget.text,
              style: context.colors.monoSmall.copyWith(
                color: context.colors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
