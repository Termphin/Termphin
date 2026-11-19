import 'package:material_ui/material_ui.dart';

import '../../screens/settings/manual_screen.dart';
import '../../services/app/manual_urls.dart';
import '../../utils/platform_info.dart';
import '../ui/app_sheet.dart';
import '../ui/clipboard_and_links.dart';

/// Opens the manual on [page], above everything else - a sheet or a dialog
/// asking for it stays where it was underneath.
///
/// Where there is no web view to read it in, the manual opens in the browser.
Future<void> openManual(BuildContext context, ManualPage page) async {
  if (!platformHas(PlatformFeature.embeddedWebView)) {
    await openExternalUrl(context, page.url);
    return;
  }
  await pushAppWindow<void>(
    context,
    rootNavigator: true,
    builder: (_) => ManualScreen(page: page),
  );
}
