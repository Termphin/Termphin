import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../utils/platform_info.dart';

/// The image on the system clipboard as PNG bytes - a screenshot, a picture
/// copied from a browser - or null when there is none. Only a computer is
/// asked: on a phone pasting into the terminal stays text only. Null too
/// when the clipboard cannot be read, which a paste treats as nothing to
/// paste rather than an error.
Future<Uint8List?> readClipboardImage() async {
  if (!isDesktopPlatform) return null;
  try {
    final image = await Pasteboard.image;
    return image == null || image.isEmpty ? null : image;
  } catch (_) {
    return null;
  }
}

/// The name an image pasted from the clipboard is uploaded under: when it
/// was pasted, to the second, so two in a row do not overwrite each other
/// in a directory that keeps names as they are.
String clipboardImageName(DateTime when) {
  String two(int value) => value.toString().padLeft(2, '0');
  final day = '${when.year}${two(when.month)}${two(when.day)}';
  final time = '${two(when.hour)}${two(when.minute)}${two(when.second)}';
  return 'clipboard-$day-$time.png';
}
