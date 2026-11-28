import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../utils/platform_info.dart';

/// Test overrides for clipboard reading and temp output directory.
@visibleForTesting
Future<Uint8List?> Function()? debugClipboardImageReader;

@visibleForTesting
Directory? debugLocalClipboardDirectory;

/// The image on the system clipboard as PNG bytes - a screenshot, a picture
/// copied from a browser - or null when there is none. Only a computer is
/// asked: on a phone pasting into the terminal stays text only. Null too
/// when the clipboard cannot be read, which a paste treats as nothing to
/// paste rather than an error.
Future<Uint8List?> readClipboardImage() async {
  if (!isDesktopPlatform) return null;
  final override = debugClipboardImageReader;
  if (override != null) return override();
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

/// Saves [png] bytes from the clipboard to a temporary local file for
/// local ("This computer") sessions, so only its path needs to be pasted.
Future<File> saveLocalClipboardImage(
  Uint8List png, {
  Directory? directory,
  DateTime? now,
}) => saveLocalTempFile(
  clipboardImageName(now ?? DateTime.now()),
  Stream.value(png),
  directory: directory,
);

/// Writes [bytes] under a unique filename inside Termphin's local temp
/// folder without overwriting an existing file.
Future<File> saveLocalTempFile(
  String fileName,
  Stream<List<int>> bytes, {
  Directory? directory,
}) async {
  final dir =
      directory ??
      debugLocalClipboardDirectory ??
      Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}termphin',
      );
  await dir.create(recursive: true);
  final dot = fileName.lastIndexOf('.');
  final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
  final ext = dot > 0 ? fileName.substring(dot) : '';
  var file = File('${dir.path}${Platform.pathSeparator}$fileName');
  for (var n = 2; await file.exists(); n++) {
    file = File('${dir.path}${Platform.pathSeparator}$stem-$n$ext');
  }
  final sink = file.openWrite();
  try {
    await sink.addStream(bytes);
    await sink.flush();
  } finally {
    await sink.close();
  }
  return file;
}
