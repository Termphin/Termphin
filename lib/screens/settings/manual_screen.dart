import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/app/manual_urls.dart';
import '../../theme/theme.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/clipboard_and_links.dart';

/// The user manual, read inside the app.
///
/// A web view rather than a bundled copy: the manual is written against the
/// current build and gets corrections between releases, so anything shipped
/// in the APK would be stale on arrival. It is also not a browser - only
/// pages on the manual's own origin load here, and every other link is handed
/// to the real browser, so a link out cannot leave the user on a page they
/// think is still the app.
///
/// Opened on [page], so help next to a feature lands on that feature.
class ManualScreen extends StatefulWidget {
  const ManualScreen({super.key, this.page = ManualPage.home});

  final ManualPage page;

  @override
  State<ManualScreen> createState() => _ManualScreenState();
}

/// The browser action opens wherever the reader has got to, not where the
/// view started.
class _ManualScreenState extends State<ManualScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  /// A failed subresource is not a failed page: an image or a font that
  /// 404s would otherwise replace a perfectly readable page with an error
  /// screen, so only a main-frame error counts.
  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.manual));
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!mounted || !error.isForMainFrame!) return;
            setState(() {
              _loading = false;
              _failed = true;
            });
          },
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url != null && ManualUrls.isManual(url)) {
              return NavigationDecision.navigate;
            }
            unawaited(_openExternally(request.url));
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(widget.page.url);
  }

  Future<void> _openExternally(String url) async {
    final t = Translations.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (mounted) AppNotifications.error(context, t.manual.openFailed);
      return;
    }
    await openExternalUrl(context, uri, failureMessage: t.manual.openFailed);
  }

  Future<void> _reload() async {
    setState(() {
      _failed = false;
      _loading = true;
    });
    await _controller.loadRequest(widget.page.url);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: AppBar(
        title: Text(t.manual.title),
        actions: [
          IconButton(
            tooltip: t.manual.openInBrowser,
            icon: const Icon(PhosphorIconsRegular.arrowSquareOut),
            onPressed: () async => _openExternally(
              await _controller.currentUrl() ?? widget.page.url.toString(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _failed
            ? _ManualError(onRetry: _reload)
            : Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                ],
              ),
      ),
    );
  }
}

class _ManualError extends StatelessWidget {
  const _ManualError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.cloudSlash,
              size: 40,
              color: context.colors.textTertiary,
            ),
            const SizedBox(height: 14),
            Text(
              t.manual.loadFailed,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              t.manual.loadFailedBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: Text(t.manual.retry)),
          ],
        ),
      ),
    );
  }
}
