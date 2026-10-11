import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/strings.g.dart';
import 'app_notifications.dart';

/// Puts [text] on the clipboard and confirms it with [message], or the
/// generic "Copied." when none is given.
Future<void> copyToClipboard(
  BuildContext context,
  String text, {
  String? message,
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  AppNotifications.success(context, message ?? t.common.copied);
}

/// Opens [uri] outside the app - a browser, a store, a mail client. When
/// nothing can open it, says so with [failureMessage], or the generic
/// "Could not open your browser." when none is given.
Future<void> openExternalUrl(
  BuildContext context,
  Uri uri, {
  String? failureMessage,
}) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    AppNotifications.error(
      context,
      failureMessage ?? t.settings.legalLinkFailed,
    );
  }
}
