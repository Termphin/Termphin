import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'file_type.dart';
import 'material_icons_map.dart';

/// File-type icon for [filename], using per-extension Material Icon Theme
/// SVGs where available and falling back to a generic Phosphor icon
/// otherwise. Directories are not handled here - callers keep their own
/// folder icon/color.
Widget buildFileIcon(
  String filename, {
  double size = 24,
  Color? fallbackColor,
}) {
  final lowerName = filename.toLowerCase();
  final dot = lowerName.lastIndexOf('.');
  final ext = dot > 0 ? lowerName.substring(dot + 1) : '';

  final iconName = materialFileNames[lowerName] ?? materialFileExtensions[ext];
  if (iconName != null) {
    return SvgPicture.asset(
      'assets/icons/material/$iconName.svg',
      width: size,
      height: size,
    );
  }

  return Icon(_fallbackIcon(filename), size: size, color: fallbackColor);
}

IconData _fallbackIcon(String filename) => switch (fileTypeOf(filename)) {
  FileKind.image => PhosphorIconsFill.image,
  FileKind.text => PhosphorIconsFill.fileText,
  FileKind.binary => PhosphorIconsFill.file,
};
