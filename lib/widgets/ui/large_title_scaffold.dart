import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../utils/platform_info.dart';

/// The reading width body content is capped to on a wide window.
const double kContentMaxWidth = 860;

/// Caps body content to a comfortable reading width and centers it on
/// desktop - a wide window would otherwise stretch lists, forms and cards
/// edge to edge instead of just giving them more breathing room. Mobile
/// keeps the full width it already had.
///
/// For anything that scrolls use [ContentGutter] instead: a box around a
/// scroll view is a box around the gesture too, so the empty margins beside
/// it are dead to touch.
class DesktopContentWidth extends StatelessWidget {
  const DesktopContentWidth({
    super.key,
    required this.child,
    this.maxWidth = kContentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Hands a scroll view the horizontal inset that centres [maxWidth] of
/// content, for the view to add to its *own* padding.
///
/// That is the whole point: [DesktopContentWidth] would centre the same
/// content by boxing the scrollable, which also shrinks the area that
/// answers a drag - a swipe started in the empty margin beside a centred
/// list scrolls nothing. Padded instead, the viewport keeps the full width
/// and only what is drawn inside it moves.
class ContentGutter extends StatelessWidget {
  const ContentGutter({
    super.key,
    required this.builder,
    this.maxWidth = kContentMaxWidth,
  });

  final Widget Function(BuildContext context, EdgeInsets gutter) builder;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => builder(
        context,
        contentGutter(context, constraints.maxWidth, maxWidth: maxWidth),
      ),
    );
  }
}

/// The inset [ContentGutter] hands out, for the odd caller that already has
/// the available width and no room for another [LayoutBuilder].
EdgeInsets contentGutter(
  BuildContext context,
  double availableWidth, {
  double maxWidth = kContentMaxWidth,
}) {
  if (!isWideLayout(context) || availableWidth <= maxWidth) {
    return EdgeInsets.zero;
  }
  return EdgeInsets.symmetric(horizontal: (availableWidth - maxWidth) / 2);
}

/// Big title + optional subtitle block, meant to be the first item of the
/// scrollable body passed to [LargeTitleScaffold] (either as a plain
/// [ListView] child or wrapped in a `SliverToBoxAdapter`).
///
/// Collapsed to a plain gap on a wide layout: the compact app bar already
/// shows the title itself at a fixed size there, so drawing this too would
/// repeat it under a second, bigger copy - the "double app bar" the
/// collapsing mobile title and this header used to trade off against each
/// other, but would now both be visible at once.
class LargeTitleHeader extends StatelessWidget {
  const LargeTitleHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.padding = const EdgeInsets.fromLTRB(16, 24, 16, 8),
  });

  final String title;
  final String? subtitle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (isWideLayout(context)) {
      return const SizedBox(height: AppTheme.spaceLg);
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.displayLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Scaffold with a large title that fades into a compact AppBar title once
/// the body scrolls past [collapseOffset]. Manages the ScrollController and
/// collapse state so screens don't have to reimplement it.
class LargeTitleScaffold extends StatefulWidget {
  const LargeTitleScaffold({
    super.key,
    required this.title,
    required this.bodyBuilder,
    this.actions,
    this.floatingActionButton,
    this.collapseOffset = 56,
    this.resizeToAvoidBottomInset,
  });

  final String title;

  /// [gutter] is the horizontal inset that centres the content on a wide
  /// window - add it to the scroll view's own padding rather than boxing the
  /// view, see [ContentGutter].
  final Widget Function(
    BuildContext context,
    ScrollController controller,
    EdgeInsets gutter,
  )
  bodyBuilder;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final double collapseOffset;
  final bool? resizeToAvoidBottomInset;

  @override
  State<LargeTitleScaffold> createState() => _LargeTitleScaffoldState();
}

/// Desktop and landscape keep a plain, fixed-size, centered bar instead of
/// the mobile-style large title that collapses into it on scroll - there
/// isn't the spare height for a giant heading to grow into. The body's
/// bottom safe area is kept: edge to edge, a list that runs past the
/// system navigation bar puts its last rows under the buttons.
class _LargeTitleScaffoldState extends State<LargeTitleScaffold> {
  final _scrollController = ScrollController();
  bool _showCollapsedTitle = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > widget.collapseOffset;
    if (shouldShow == _showCollapsedTitle) return;
    setState(() => _showCollapsedTitle = shouldShow);
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = isWideLayout(context) || _showCollapsedTitle;
    return Scaffold(
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      appBar: AppBar(
        shape: collapsed
            ? Border(
                bottom: BorderSide(
                  color: context.colors.surfaceBorder,
                  width: 1,
                ),
              )
            : const Border(),
        title: AnimatedOpacity(
          duration: AppTheme.interactiveDuration,
          opacity: collapsed ? 1 : 0,
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        actions: widget.actions,
      ),
      floatingActionButton: widget.floatingActionButton,
      body: SafeArea(
        top: false,
        child: ContentGutter(
          builder: (context, gutter) =>
              widget.bodyBuilder(context, _scrollController, gutter),
        ),
      ),
    );
  }
}
