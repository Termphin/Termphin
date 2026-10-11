import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/platform_info.dart';
import '../ui/app_sheet.dart';

/// What the page in front puts in the title bar on a desktop: its name and
/// its actions.
class DesktopPageBarData {
  const DesktopPageBarData({required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;
}

/// The title and actions of the page on screen, which the title bar draws
/// in place of a second bar under itself.
///
/// A window has one bar along its top. A page that brought an `AppBar` of
/// its own stacked another 44 px of chrome under it to say what the sidebar
/// already highlights; here the page hands the title bar what that bar held
/// (see [DesktopPageHeader]) and keeps the height for its list.
class DesktopPageBar extends ChangeNotifier {
  DesktopPageBar._();

  static final instance = DesktopPageBar._();

  final _sources = <Object, DesktopPageBarData>{};
  bool _notifyScheduled = false;

  /// The page in front - the last to publish, which is the one on top.
  DesktopPageBarData? get current =>
      _sources.isEmpty ? null : _sources.values.last;

  void _set(Object owner, DesktopPageBarData data) {
    _sources.remove(owner);
    _sources[owner] = data;
    _changed();
  }

  void _remove(Object owner) {
    if (_sources.remove(owner) != null) _changed();
  }

  /// Deferred: a page finds out it is in front while it is building.
  void _changed() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

/// Publishes a page's [title] and [actions] to the title bar while the page
/// is the one in front: its section is on screen (`TickerMode`) and no page
/// is over it.
///
/// [replacesAppBar] says whether a page should leave its own bar out. Only
/// a page in the window itself does - one opened as a dialog keeps its bar,
/// which is that dialog's title and where its X is.
class DesktopPageHeader extends StatefulWidget {
  const DesktopPageHeader({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final List<Widget> actions;
  final Widget child;

  static bool replacesAppBar(BuildContext context) =>
      isDesktopPlatform && !AppModalScope.isDialog(context);

  @override
  State<DesktopPageHeader> createState() => _DesktopPageHeaderState();
}

class _DesktopPageHeaderState extends State<DesktopPageHeader> {
  void _sync() {
    final front =
        DesktopPageHeader.replacesAppBar(context) &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (front) {
      DesktopPageBar.instance._set(
        this,
        DesktopPageBarData(title: widget.title, actions: widget.actions),
      );
    } else {
      DesktopPageBar.instance._remove(this);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(DesktopPageHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    DesktopPageBar.instance._remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
