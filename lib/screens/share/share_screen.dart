import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app.dart';
import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../services/platform/share_intent_service.dart';
import '../../services/security/lock_service.dart';
import '../../services/settings/app_settings.dart';
import '../../theme/theme.dart';
import '../../widgets/share/share_preview.dart';
import '../../widgets/ui/empty_state.dart';
import '../lock_screen.dart';
import '../search/global_search_launcher.dart';
import 'share_upload_screen.dart';

/// Where `ShareActivity`'s engine starts, instead of the app's `main`.
///
/// None of the app's startup runs here: no sessions are restored, no
/// foreground service, no analytics. The settings are read for the theme
/// and the folder picker; everything else is read from storage as the
/// screens ask for it.
Future<void> runShareApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppSettings();
  runApp(const SshClientApp(home: ShareGate()));
}

/// The PIN first, if there is one - a share is no way around it - then
/// [ShareScreen].
class ShareGate extends StatefulWidget {
  const ShareGate({super.key, this.take, this.finish});

  /// Stand-ins for the native side, for tests.
  final Future<SharedContent?> Function()? take;
  final Future<void> Function()? finish;

  @override
  State<ShareGate> createState() => _ShareGateState();
}

class _ShareGateState extends State<ShareGate> {
  bool? _locked;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final locked = await LockService.instance.isLockEnabled;
    if (mounted) setState(() => _locked = locked);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_locked) {
      null => Scaffold(backgroundColor: context.colors.backgroundPrimary),
      true => LockScreen(onUnlocked: () => setState(() => _locked = false)),
      false => ShareScreen(take: widget.take, finish: widget.finish),
    };
  }
}

/// Sends what another app shared to a folder on one of the machines, like
/// sharing to a chat: pick a machine, pick a folder, and once it is all
/// uploaded the screen closes on its own and the sharing app is back.
///
/// Backing out of a folder returns to the machines; backing out of those
/// closes the screen with nothing sent.
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key, this.take, this.finish});

  final Future<SharedContent?> Function()? take;
  final Future<void> Function()? finish;

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final _heroTag = Object();

  /// Why nothing can be sent, when that is the case.
  String? _problem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _finish() =>
      (widget.finish ?? ShareIntentService.instance.finish)();

  Future<void> _run() async {
    final content = await (widget.take ?? ShareIntentService.instance.take)();
    if (!mounted) return;
    if (content == null) {
      await _finish();
      return;
    }
    final t = Translations.of(context);
    if (content.files.isEmpty) {
      setState(
        () => _problem = content.hadText ? t.share.textOnly : t.share.noFiles,
      );
      return;
    }

    while (true) {
      if (!mounted) return;
      SshProfile? picked;
      await openGlobalSearch(
        context,
        heroTag: _heroTag,
        hint: t.share.searchHint,
        header: SharePreview(content: content),
        onPick: (profile) => picked = profile,
      );
      final profile = picked;
      if (profile == null || !mounted) break;
      final sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ShareUploadScreen(profile: profile, content: content),
        ),
      );
      if (sent ?? false) break;
    }
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final problem = _problem;
    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      body: problem == null
          ? null
          : SafeArea(
              child: EmptyStatePanel(
                icon: PhosphorIconsRegular.fileX,
                title: problem,
                action: FilledButton(
                  onPressed: () => unawaited(_finish()),
                  child: Text(t.common.close),
                ),
              ),
            ),
    );
  }
}
