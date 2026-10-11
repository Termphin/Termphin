import 'package:flutter/material.dart';

import '../../screens/settings/manual_screen.dart';
import '../../services/app/manual_urls.dart';
import '../../utils/platform_info.dart';
import 'app_sheet.dart';
import 'clipboard_and_links.dart';

/// Opens the manual on [page], above everything else - a sheet or a dialog
/// asking for it stays where it was underneath.
///
/// Where there is no web view to read it in, the manual opens in the browser.
Future<void> openManual(BuildContext context, ManualPage page) async {
  if (!platformHas(PlatformFeature.embeddedWebView)) {
    await openExternalUrl(context, page.url);
    return;
  }
  if (isDesktopPlatform) {
    await pushAppWindow<void>(
      context,
      builder: (_) => ManualScreen(page: page),
    );
    return;
  }
  await Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => ManualScreen(page: page)));
}
