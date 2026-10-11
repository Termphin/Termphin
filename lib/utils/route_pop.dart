import 'package:flutter/widgets.dart';

/// Pops [route] with [result], closing anything that was pushed on top of it.
///
/// A plain `Navigator.pop` hands the result to whatever route is topmost, so a
/// menu left open when a save finishes receives a value of the wrong type and
/// throws.
void popRouteWithResult<T>(
  NavigatorState navigator,
  Route<dynamic>? route,
  T result,
) {
  if (route != null && !route.isCurrent) {
    navigator.popUntil((r) => identical(r, route));
  }
  navigator.pop(result);
}
