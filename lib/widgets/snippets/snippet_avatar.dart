import 'package:flutter/material.dart';

import '../profiles/profile_avatar.dart';

/// The badge on a snippet, in the same frame a machine's avatar uses.
///
/// Fixed on purpose: it is here to break the wall of text a list of commands
/// otherwise is, not to be decorated. There is nothing to pick, so a snippet
/// carries no icon or colour of its own.
class SnippetAvatar extends StatelessWidget {
  const SnippetAvatar({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) =>
      ProfileAvatar(iconName: 'terminal', colorHex: null, size: size);
}
