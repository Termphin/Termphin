import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/app/whats_new_service.dart';
import '../../services/completion/command_completion.dart';
import '../../services/settings/setting.dart';
import '../../theme/theme.dart';
import '../ui/modal_actions.dart';

/// The settings a highlight may offer a switch for, by preferences key.
///
/// Closed on purpose: the yaml names a key, and only one listed here draws
/// anything - `whats_new_test.dart` fails on a key that is not.
final Map<
  String,
  ({Setting<bool> setting, String Function(Translations) label})
>
whatsNewToggles = {
  commandSuggestionsSetting.key: (
    setting: commandSuggestionsSetting,
    label: (t) => t.settings.commandSuggestions,
  ),
};

/// The tallest an illustration is drawn; a portrait recording is narrowed to
/// fit rather than pushing the words off the page. Tall enough for a screen
/// recording cropped to about 3:2 to still span the card's width.
const _kMaxImageHeight = 250.0;

/// Below this much height the illustration is dropped rather than shrunk.
///
/// Landscape on a phone leaves around 300dp inside a dialog. An image scaled
/// to fit that takes the room the words need and stops being legible itself,
/// so the text-only layout is the better of the two - the same page the
/// author gets when they write a highlight with no image at all.
const _kImageMinHeight = 440.0;

/// The most a page may take, with and without its illustration.
///
/// A ceiling, not a height: a card with two short lines on it is two short
/// lines tall. Anything past this scrolls inside the page rather than growing
/// the dialog.
const _kMaxPageHeightWithImage = 420.0;
const _kMaxPageHeightTextOnly = 260.0;

/// Dots and button below the pages, plus the padding around them - taken off
/// the window before a page height is chosen so the card cannot outgrow the
/// screen on a short one.
const _kChromeHeight = 132.0;

/// Shows the what's-new popup for [highlights] and completes once dismissed.
///
/// One highlight per page, paged through in order. Returns immediately if
/// there is nothing to show, so callers do not have to check first.
Future<void> showWhatsNewModal(
  BuildContext context,
  List<ReleaseHighlight> highlights,
) {
  if (highlights.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WhatsNewModal(highlights: highlights),
  );
}

/// Shows highlight [id] as an explanation of a feature, from beside its
/// setting: the same page, without the announcement's label, and without its
/// switch, which the caller already sits next to. Nothing is marked seen, and
/// a stray tap outside closes it - this was asked for.
Future<void> showFeatureExplainer(BuildContext context, String id) async {
  final highlight = await WhatsNewService.instance.highlight(id);
  if (highlight == null || !context.mounted) return;
  return showDialog<void>(
    context: context,
    builder: (_) => WhatsNewModal(highlights: [highlight], announce: false),
  );
}

/// An ⓘ beside a setting's title that opens [explainerId] through
/// [showFeatureExplainer].
///
/// Sized to sit against the title it belongs to: an `IconButton`'s 48px
/// target would set it a thumb's width away and taller than the text.
class FeatureInfoButton extends StatelessWidget {
  const FeatureInfoButton({super.key, required this.explainerId});

  final String explainerId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: Translations.of(context).settings.howItWorks,
        child: Semantics(
          button: true,
          child: InkResponse(
            radius: 16,
            onTap: () => showFeatureExplainer(context, explainerId),
            child: SizedBox.square(
              dimension: 28,
              child: Icon(
                PhosphorIconsRegular.info,
                size: 16,
                color: context.colors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WhatsNewModal extends StatefulWidget {
  const WhatsNewModal({
    super.key,
    required this.highlights,
    this.announce = true,
  });

  final List<ReleaseHighlight> highlights;

  /// False when a feature is being explained rather than announced: no "now
  /// available" label and no switch.
  final bool announce;

  @override
  State<WhatsNewModal> createState() => _WhatsNewModalState();
}

/// The dialog's own inset is the only height it cannot use. The taller page
/// ceiling is reserved for sets that actually carry an illustration - a set
/// written without one has no use for the room and should not be allowed to
/// sprawl into it.
class _WhatsNewModalState extends State<WhatsNewModal> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == widget.highlights.length - 1;

  void _advance() {
    if (_isLast) {
      Navigator.of(context).pop();
      return;
    }
    _controller.nextPage(
      duration: AppTheme.motionSlow,
      curve: Curves.easeOutCubic,
    );
  }

  /// The pages, sized by their own content rather than by a written-down
  /// height - up to whatever ceiling the caller constrains this to.
  ///
  /// A single highlight is drawn as itself. There is no carousel to page
  /// through, so there is no viewport in the way of it reporting how tall it
  /// is, and nothing to duplicate.
  ///
  /// Several need a `PageView`, which is a viewport: it takes every pixel it
  /// is offered and reports no height of its own, so something else has to
  /// say how tall a page is. The stack is that something - every page laid
  /// out at once and left unpainted, which makes the stack exactly as tall as
  /// the tallest of them. The tallest, not each page's own: a carousel hands
  /// every page the same constraints, so a height that followed the visible
  /// page would make the card jump on each swipe.
  Widget _pages(bool showImages) {
    if (widget.highlights.length == 1) {
      return _HighlightPage(
        highlight: widget.highlights.single,
        showImage: showImages,
        announce: widget.announce,
      );
    }
    return Stack(
      children: [
        for (final highlight in widget.highlights)
          Visibility(
            visible: false,
            maintainSize: true,
            maintainState: true,
            maintainAnimation: true,
            child: _HighlightPage(
              highlight: highlight,
              showImage: showImages,
              announce: widget.announce,
            ),
          ),
        Positioned.fill(
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.highlights.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (_, index) => _HighlightPage(
              highlight: widget.highlights[index],
              showImage: showImages,
              announce: widget.announce,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final available = media.size.height - 80;
    final showImages = available >= _kImageMinHeight;
    final withImages =
        showImages && widget.highlights.any((h) => h.image != null);
    final maxPageHeight = math.min(
      withImages ? _kMaxPageHeightWithImage : _kMaxPageHeightTextOnly,
      math.max(available - _kChromeHeight, 120.0),
    );

    return Dialog(
      backgroundColor: colors.surfaceElevated,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: colors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxPageHeight),
              child: _pages(showImages),
            ),
            if (widget.highlights.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: _PageDots(
                  count: widget.highlights.length,
                  current: _page,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: ModalActions(
                primary: FilledButton(
                  onPressed: _advance,
                  child: Text(_isLast ? t.whatsNew.gotIt : t.whatsNew.next),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A highlight that outlives its screenshot reads as a text page, not as a
/// broken release.
class _HighlightPage extends StatelessWidget {
  const _HighlightPage({
    required this.highlight,
    required this.showImage,
    required this.announce,
  });

  final ReleaseHighlight highlight;
  final bool showImage;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final image = highlight.image;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image != null && showImage) ...[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _kMaxImageHeight),
                child: AspectRatio(
                  aspectRatio: highlight.imageAspect ?? 16 / 7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: Image.asset(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (announce) ...[
            Text(
              t.whatsNew.nowAvailable.toUpperCase(),
              style: textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            highlight.title,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            highlight.body,
            style: textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          if (announce)
            if (whatsNewToggles[highlight.setting] case final toggle?) ...[
              const SizedBox(height: 12),
              ValueListenableBuilder<bool>(
                valueListenable: toggle.setting,
                builder: (context, enabled, _) => SwitchListTile(
                  key: ValueKey('whatsNewToggle-${highlight.setting}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(toggle.label(t)),
                  value: enabled,
                  activeThumbColor: colors.primary,
                  onChanged: toggle.setting.set,
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: AppTheme.interactiveDuration,
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 6,
            width: i == current ? 18 : 6,
            decoration: BoxDecoration(
              color: i == current ? colors.primary : colors.surfaceBorderStrong,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
          ),
      ],
    );
  }
}
