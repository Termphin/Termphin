import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../theme/theme.dart';
import 'global_search_screen.dart';

/// Height of the search box, closed and open, so the flight between the two
/// changes only width and position.
const double kSearchBoxHeight = 52;

/// The search box's shape: the field fill, a border that turns accent when
/// the box is open, and the magnifying glass. The launcher, the open field
/// and the flight between them all draw this, so nothing jumps at either end.
class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.child, this.focused = 0});

  final Widget child;

  /// 0 closed, 1 open; in between during the flight.
  final double focused;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: kSearchBoxHeight,
        decoration: BoxDecoration(
          color: colors.fieldFill,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: Color.lerp(colors.surfaceBorder, colors.primary, focused)!,
            width: 1 + 0.2 * focused,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppTheme.space14),
            Icon(
              PhosphorIconsRegular.magnifyingGlass,
              size: AppTheme.icon18,
              color: Color.lerp(colors.textTertiary, colors.primary, focused),
            ),
            const SizedBox(width: AppTheme.space10),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// The search box at the top of a main screen. It does not filter the list
/// under it: a tap flies it to the top of [GlobalSearchScreen], which searches
/// every machine, session, group, snippet and key at once.
///
/// [heroTag] has to differ per screen - all main screens stay mounted side by
/// side, and two heroes with one tag in a route is an error. [onPick] opens
/// it to pick one machine out of [pickFrom] instead (see [GlobalSearchScreen]).
class GlobalSearchLauncher extends StatelessWidget {
  const GlobalSearchLauncher({
    super.key,
    required this.heroTag,
    this.hint,
    this.pickFrom,
    this.onPick,
  });

  final Object heroTag;
  final String? hint;
  final List<SshProfile>? pickFrom;
  final ValueChanged<SshProfile>? onPick;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final hint = this.hint ?? t.globalSearch.hint;
    final box = Hero(
      tag: heroTag,
      flightShuttleBuilder: searchBoxFlight(hint),
      child: SearchBox(
        child: Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTheme.uiFamily,
            fontSize: AppTheme.font14,
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openGlobalSearch(
          context,
          heroTag: heroTag,
          hint: this.hint,
          pickFrom: pickFrom,
          onPick: onPick,
        ),
        child: box,
      ),
    );
  }
}

/// What flies between the launcher and the open field: the box alone, its
/// border warming to the accent on the way up and cooling on the way back.
/// Neither end's own child flies - a live `TextField` squeezed through every
/// width in between would reflow its text each frame.
HeroFlightShuttleBuilder searchBoxFlight(String hint) =>
    (context, animation, direction, fromContext, toContext) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) => SearchBox(
          focused: curved.value,
          child: Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: TextStyle(
              fontFamily: AppTheme.uiFamily,
              fontSize: AppTheme.font14,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      );
    };

Future<void> openGlobalSearch(
  BuildContext context, {
  required Object heroTag,
  String? hint,
  List<SshProfile>? pickFrom,
  ValueChanged<SshProfile>? onPick,
  Widget? header,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: AppTheme.motionPage,
      reverseTransitionDuration: AppTheme.motionMedium,
      pageBuilder: (_, _, _) => GlobalSearchScreen(
        heroTag: heroTag,
        hint: hint,
        pickFrom: pickFrom,
        onPick: onPick,
        header: header,
      ),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}
