import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../../utils/link_metadata.dart';
import '../ui/clipboard_and_links.dart';

/// Where the preview's top edge goes for a tap at [tapY] (global). It opens
/// on whichever side of the tap has more room, and stays inside what the
/// keyboard leaves visible - [keyboardInset] is measured from the bottom.
double linkPopupTop({
  required double tapY,
  required double screenHeight,
  required double keyboardInset,
  required double popupHeight,
  double margin = 12,
}) {
  final visibleBottom = screenHeight - keyboardInset;
  final showAbove = tapY > visibleBottom / 2;
  final top = showAbove ? tapY - popupHeight - margin : tapY + margin;
  final maxTop = visibleBottom - popupHeight - margin;
  return maxTop < margin ? margin : top.clamp(margin, maxTop);
}

class LinkPreviewPopup extends StatefulWidget {
  const LinkPreviewPopup({
    super.key,
    required this.url,
    required this.tapY,
    required this.onDismiss,
    this.fetcher,
  });

  final String url;
  final double tapY;
  final VoidCallback onDismiss;

  /// Where the page metadata comes from. Only overridden in tests - the real
  /// one is an HTTP request fired from `initState`, which is not something a
  /// test of what this draws should have to make.
  @visibleForTesting
  final Future<LinkMetadata> Function(String url)? fetcher;

  @override
  State<LinkPreviewPopup> createState() => _LinkPreviewPopupState();
}

class _LinkPreviewPopupState extends State<LinkPreviewPopup> {
  LinkMetadata? _meta;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchMeta();
  }

  Future<void> _fetchMeta() async {
    final meta = await (widget.fetcher ?? _fetch)(widget.url);
    if (mounted) {
      setState(() {
        _meta = meta;
        _loading = false;
      });
    }
  }

  Future<LinkMetadata> _fetch(String url) async {
    try {
      final uri = Uri.parse(url);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      req.headers
        ..set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (compatible; Termphin/1.0)',
        )
        ..set(HttpHeaders.acceptHeader, 'text/html');
      final res = await req.close().timeout(const Duration(seconds: 8));

      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) break;
      }
      client.close();

      return LinkMetadata.parse(
        utf8.decode(bytes, allowMalformed: true),
        base: uri,
      );
    } catch (_) {
      return const LinkMetadata();
    }
  }

  Future<void> _open() async {
    await openExternalUrl(context, Uri.parse(widget.url));
    widget.onDismiss();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    final hasText = _meta?.title != null || _meta?.description != null;
    final hasImg = _meta?.imageUrl != null;

    return Container(
      width: 272,
      decoration: BoxDecoration(
        color: context.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: context.colors.surfaceBorderStrong),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            _PreviewRow(
              leading: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.primary,
                ),
              ),
              title: t.linkPreview.loading,
              subtitle: null,
            )
          else if (hasText || hasImg)
            _PreviewRow(
              leading: hasImg
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      child: Image.network(
                        _meta!.imageUrl!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _FallbackThumb(),
                      ),
                    )
                  : const _FallbackThumb(),
              title: _meta?.title,
              subtitle: _meta?.description,
            )
          else
            _PreviewRow(
              leading: const _FallbackThumb(),
              title: t.linkPreview.noPreview,
              subtitle: null,
            ),

          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colors.surfaceDivider),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsRegular.link,
                  size: 12,
                  color: context.colors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.url,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colors.surfaceDivider),
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _ActionBtn(
                      icon: PhosphorIconsFill.copy,
                      label: t.linkPreview.copyLink,
                      onTap: _copy,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: context.colors.surfaceDivider,
                  ),
                  Expanded(
                    child: _ActionBtn(
                      icon: PhosphorIconsFill.arrowSquareOut,
                      label: t.terminal.openInBrowser,
                      onTap: _open,
                      primary: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.leading,
    required this.title,
    required this.subtitle,
  });

  final Widget leading;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackThumb extends StatelessWidget {
  const _FallbackThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: context.colors.surfaceOffset,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Icon(
        PhosphorIconsFill.globe,
        size: 22,
        color: context.colors.textSecondary,
      ),
    );
  }
}

/// The popup is a fixed 272 wide and two of these sit side by side, so a
/// longer translation has to give rather than overflow.
class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final color = primary
        ? context.colors.primary
        : context.colors.textSecondary;
    return Material(
      color: context.colors.surfaceElevated.invisible,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
