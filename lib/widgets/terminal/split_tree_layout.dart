import 'package:material_ui/material_ui.dart';

import '../../models/ssh_profile.dart';
import '../../screens/terminal/state/split_layout.dart';
import 'split_pane_chrome.dart';

/// A group of sessions laid out as its split tree, on a desktop: each pane
/// under a bar naming it, lit while it has focus, and a divider between
/// every two halves that drags their split.
///
/// A phone keeps `SplitTabLayout`, two panes folded around its keyboard;
/// here there is no keyboard to make room for and any number of panes. With
/// [zoomedId] in the tree, that pane takes the whole room and the rest wait
/// behind it, still connected. [onPaneSized] hears each pane's size, so a
/// new split can go along the longer side and refuse to make panes too small
/// to read.
class SplitTreeLayout extends StatelessWidget {
  const SplitTreeLayout({
    super.key,
    required this.root,
    required this.paneBuilder,
    required this.focusedId,
    required this.profileFor,
    required this.labelFor,
    required this.onFocusPane,
    required this.onRatioChanged,
    required this.onDividerHeldChanged,
    this.onPaneSized,
    this.zoomedId,
  });

  final SplitNode root;
  final Widget Function(String sessionId) paneBuilder;
  final String focusedId;
  final SshProfile Function(String sessionId) profileFor;
  final String Function(String sessionId) labelFor;
  final ValueChanged<String> onFocusPane;
  final void Function(SplitBranch branch, double ratio) onRatioChanged;
  final ValueChanged<bool> onDividerHeldChanged;
  final void Function(String sessionId, Size size)? onPaneSized;
  final String? zoomedId;

  @override
  Widget build(BuildContext context) {
    final zoomed = zoomedId;
    if (zoomed != null && root.leaves.contains(zoomed)) {
      return _pane(zoomed);
    }
    return _node(root);
  }

  Widget _node(SplitNode node) => switch (node) {
    SplitLeaf(:final id) => _pane(id),
    SplitBranch() => _branch(node),
  };

  Widget _branch(SplitBranch branch) {
    final sideBySide = branch.axis == SplitAxis.sideBySide;
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = sideBySide ? constraints.maxWidth : constraints.maxHeight;
        final usable = (total - kSplitDividerThickness).clamp(0.0, total);
        final firstSize = usable * branch.ratio;
        return Flex(
          direction: sideBySide ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: sideBySide ? firstSize : null,
              height: sideBySide ? null : firstSize,
              child: _node(branch.first),
            ),
            SplitDivider(
              axis: sideBySide ? Axis.horizontal : Axis.vertical,
              onHeld: onDividerHeldChanged,
              onDrag: (delta) {
                if (usable <= 0) return;
                onRatioChanged(branch, (firstSize + delta) / usable);
              },
            ),
            Expanded(child: _node(branch.second)),
          ],
        );
      },
    );
  }

  Widget _pane(String id) {
    return LayoutBuilder(
      key: ValueKey('splitTreePane-$id'),
      builder: (context, constraints) {
        final report = onPaneSized;
        if (report != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => report(id, constraints.biggest),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SplitPaneHeader(
              profile: profileFor(id),
              label: labelFor(id),
              focused: id == focusedId,
              onTap: () => onFocusPane(id),
            ),
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) {
                  if (id != focusedId) onFocusPane(id);
                },
                child: paneBuilder(id),
              ),
            ),
          ],
        );
      },
    );
  }
}
