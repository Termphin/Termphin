import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/release_notes_screen.dart';
import '../../services/platform/app_updater.dart';
import '../../services/platform/appcast_parser.dart';
import '../../services/platform/desktop_window.dart';
import '../../theme/theme.dart';
import '../ui/app_sheet.dart';

/// Height of the bottom status bar shown across desktop platforms.
const double kDesktopStatusBarHeight = AppTheme.space24;

/// Thin status strip at the bottom of the desktop window showing the running
/// version (and an update action when a Linux AppImage update is available).
class DesktopStatusBar extends StatefulWidget {
  const DesktopStatusBar({
    super.key,
    required this.navigatorContext,
    this.packageInfoLoader,
  });

  final BuildContext? Function() navigatorContext;
  final Future<PackageInfo> Function()? packageInfoLoader;

  @override
  State<DesktopStatusBar> createState() => _DesktopStatusBarState();
}

class _DesktopStatusBarState extends State<DesktopStatusBar> {
  String? _version;
  String? _buildNumber;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    try {
      final loader = widget.packageInfoLoader ?? PackageInfo.fromPlatform;
      final info = await loader();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (_) {}
  }

  void _openReleaseNotes() {
    final ctx = widget.navigatorContext();
    if (ctx == null || !ctx.mounted) return;
    pushAppWindow<void>(ctx, builder: (_) => const ReleaseNotesScreen());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = Translations.of(context);
    final version = _version;
    final buildNumber = _buildNumber;
    final versionText = version == null
        ? null
        : (buildNumber != null && buildNumber.isNotEmpty)
        ? t.updates.versionLabel(version: version, build: buildNumber)
        : 'v$version';

    return ValueListenableBuilder<bool>(
      valueListenable: DesktopWindow.instance.focused,
      builder: (context, focused, _) => AnimatedOpacity(
        opacity: focused ? 1 : 0.72,
        duration: AppTheme.interactiveDuration,
        child: Container(
          key: const ValueKey('desktopStatusBar'),
          height: kDesktopStatusBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12),
          decoration: BoxDecoration(
            color: colors.backgroundPrimary,
            border: Border(top: BorderSide(color: colors.surfaceBorder)),
          ),
          child: Row(
            children: [
              const Spacer(),
              ValueListenableBuilder<AppcastEntry?>(
                valueListenable: AppUpdater.instance.availableUpdate,
                builder: (context, update, _) {
                  if (update == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: AppTheme.space8),
                    child: InkWell(
                      onTap: () => unawaited(
                        AppUpdater.instance.installAvailable(
                          context: widget.navigatorContext(),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space6,
                          vertical: AppTheme.space2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.warningHighlight,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusXs,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIconsRegular.arrowCircleUp,
                              size: AppTheme.icon12,
                              color: colors.warning,
                            ),
                            const SizedBox(width: AppTheme.space4),
                            Text(
                              t.updates.statusBarAvailable(
                                version: update.version,
                              ),
                              style: TextStyle(
                                fontSize: AppTheme.font11,
                                fontWeight: FontWeight.w600,
                                color: colors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (versionText != null)
                Tooltip(
                  message: t.window.releaseNotes,
                  child: InkWell(
                    onTap: _openReleaseNotes,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space6,
                        vertical: AppTheme.space2,
                      ),
                      child: Text(
                        versionText,
                        style: TextStyle(
                          fontSize: AppTheme.font11,
                          color: colors.textTertiary,
                        ),
                      ),
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
