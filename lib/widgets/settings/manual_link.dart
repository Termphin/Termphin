import 'package:flutter/material.dart';

import '../../screens/settings/manual_screen.dart';
import '../../services/app/manual_urls.dart';

/// Opens the manual on [page], above everything else - a sheet or a dialog
/// asking for it stays where it was underneath.
Future<void> openManual(BuildContext context, ManualPage page) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => ManualScreen(page: page)));
}
