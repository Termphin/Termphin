import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/platform_info.dart';
import 'app_sheet.dart';

/// One step of the path shown in the desktop title bar: a page's title, and
/// what a click on it does - go back to that page.
class BreadcrumbEntry {
  const BreadcrumbEntry(this.label, this.onTap);

  final String label;
  final VoidCallback? onTap;
}

/// The path to the page on screen, for the title bar to draw. Empty while a
/// section sits at its own root, which needs no path.
final desktopBreadcrumb = ValueNotifier<List<BreadcrumbEntry>>(const []);

/// Opens a page from a list or a settings row.
///
/// On a phone that is a page over the whole app with a back arrow, as it has
/// always been. On a desktop the page opens inside the section it was opened
/// from - beside the sidebar, which stays where it is - with no back arrow:
/// the path to it is in the title bar, every step of it clickable, and Esc or
/// the mouse's back button goes up one.
///
/// [window] opens it as a window over the screen instead - for settings, where
/// a page is something to change and close, and the list it came from is
/// better left in view behind it than swapped out for it. Opened from
/// somewhere with no section around it - a form's dialog, a session - there
/// is no sidebar to open beside, so it gets a window of its own over the app
/// instead of a page that hides everything.
Future<T?> pushAppPage<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required String title,
  bool window = false,
}) {
  final navigator = Navigator.of(context);
  if (isDesktopPlatform) {
    if (window) {
      return pushAppWindow<T>(
        context,
        builder: builder,
        size: AppWindowSize.medium,
      );
    }
    if (navigator == Navigator.of(context, rootNavigator: true)) {
      return pushAppWindow<T>(context, builder: builder);
    }
    return navigator.push<T>(
      DesktopPageRoute<T>(builder: builder, title: title),
    );
  }
  return navigator.push<T>(
    MaterialPageRoute<T>(
      builder: builder,
      settings: RouteSettings(name: title),
    ),
  );
}

/// A page on a desktop: no implied back arrow, and a short fade rather than
/// a phone's slide in from the edge.
class DesktopPageRoute<T> extends MaterialPageRoute<T> {
  DesktopPageRoute({required super.builder, required String title})
    : super(settings: RouteSettings(name: title));

  @override
  bool get impliesAppBarDismissal => false;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 100);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  );
}

/// A sidebar section's own navigator, so what it opens stays beside the
/// sidebar instead of covering it. Desktop only: a phone has no sidebar to
/// keep, and its back gesture belongs to the one root navigator.
///
/// [active] is whether the section is the one on screen - only that one
/// writes [desktopBreadcrumb].
class SectionNavigator extends StatefulWidget {
  const SectionNavigator({
    super.key,
    required this.label,
    required this.active,
    required this.child,
  });

  final String label;
  final bool active;
  final Widget child;

  @override
  State<SectionNavigator> createState() => SectionNavigatorState();
}

class SectionNavigatorState extends State<SectionNavigator> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final _observer = _StackObserver(_onStackChanged);

  /// Back to the section's own root: what a click on an already selected
  /// sidebar entry does.
  void popToRoot() =>
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);

  /// Up one page, if there is one to go up from.
  bool pop() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || !navigator.canPop()) return false;
    navigator.pop();
    return true;
  }

  bool get canPop => _navigatorKey.currentState?.canPop() ?? false;

  @override
  void didUpdateWidget(SectionNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
    }
  }

  /// Publishes after the frame: a route is pushed mid-build of the
  /// navigator, and the title bar listening to the path is elsewhere in the
  /// tree and must not be dirtied then.
  void _onStackChanged() {
    if (!mounted || !widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
  }

  void _publish() {
    if (!mounted || !widget.active) return;
    final stack = _observer.stack;
    if (stack.length <= 1) {
      desktopBreadcrumb.value = const [];
      return;
    }
    desktopBreadcrumb.value = [
      for (var i = 0; i < stack.length; i++)
        BreadcrumbEntry(
          i == 0 ? widget.label : (stack[i].settings.name ?? ''),
          i == stack.length - 1
              ? null
              : () {
                  final target = stack[i];
                  _navigatorKey.currentState?.popUntil((r) => r == target);
                },
        ),
    ];
  }

  /// The mouse's own back button goes up a page - a desktop user reaches for
  /// it before looking for anything on screen - and so does Esc, which at
  /// the section's root goes on to whatever else wants it.
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons & kBackMouseButton != 0) pop();
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              pop()) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Navigator(
          key: _navigatorKey,
          observers: [_observer],
          onGenerateRoute: (settings) => DesktopPageRoute<void>(
            builder: (_) => widget.child,
            title: widget.label,
          ),
        ),
      ),
    );
  }
}

class _StackObserver extends NavigatorObserver {
  _StackObserver(this.onChanged);

  final VoidCallback onChanged;
  final stack = <Route<dynamic>>[];

  bool _isPage(Route<dynamic> route) => route is PageRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isPage(route)) return;
    stack.add(route);
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (stack.remove(route)) onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (stack.remove(route)) onChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : stack.indexOf(oldRoute);
    if (at >= 0 && newRoute != null && _isPage(newRoute)) {
      stack[at] = newRoute;
    } else if (at >= 0) {
      stack.removeAt(at);
    }
    onChanged();
  }
}
