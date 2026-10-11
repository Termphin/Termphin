import 'package:shared_preferences/shared_preferences.dart';

import '../app/onboarding_service.dart';
import 'setting.dart';

/// Where the upload-file tool puts a picked file. `currentDirectory` drops
/// it exactly where the shell already is; `tmp` is the server's scratch
/// directory; `ask` opens a folder picker, starting from the shell's
/// directory when the agent knows it.
enum UploadDestination { tmp, currentDirectory, ask }

const kUploadDestinationPrefsKey = 'upload_destination';

/// The `whats_new.yaml` page that explains fast upload, opened from beside
/// its setting.
const kFastUploadExplainerId = 'fast-upload';

final Setting<UploadDestination> uploadDestinationSetting = Setting.option(
  kUploadDestinationPrefsKey,
  fallback: UploadDestination.ask,
  values: UploadDestination.values,
);

const kUploadDestinationLegacyPinnedPrefsKey =
    'upload_destination_legacy_pinned';

const kUploadDestinationAskPinnedPrefsKey = 'upload_destination_ask_pinned';

/// The default moved from `tmp` to `currentDirectory` on 2026-09-30, then to
/// `ask` on 2026-10-02. Someone who was already using the app and never
/// picked one keeps whatever was the default when they started, so it is
/// written down for them once; a fresh install is marked done untouched.
Future<void> pinLegacyUploadDestination() async {
  final preferences = await SharedPreferences.getInstance();
  final existingUser =
      preferences.getBool(kOnboardingCompletedPrefsKey) ?? false;
  for (final (flag, legacy) in [
    (kUploadDestinationLegacyPinnedPrefsKey, UploadDestination.tmp),
    (kUploadDestinationAskPinnedPrefsKey, UploadDestination.currentDirectory),
  ]) {
    if (preferences.getBool(flag) ?? false) continue;
    if (existingUser && !preferences.containsKey(kUploadDestinationPrefsKey)) {
      await preferences.setString(kUploadDestinationPrefsKey, legacy.name);
    }
    await preferences.setBool(flag, true);
  }
}

const kUploadAutoPastePrefsKey = 'upload_auto_paste';

/// Whether a finished upload writes its remote paths at the cursor itself
/// instead of offering to.
///
/// Off by default, and deliberately so: the paths land in whatever the shell
/// is in the middle of, so an upload started while a command was half-typed
/// writes into it. Someone whose habit is upload-then-run pays for that safety
/// with a tap every time, which is what this is for - the risk is theirs to
/// accept, once, rather than being asked at every upload.
final Setting<bool> uploadAutoPasteSetting = Setting.boolean(
  kUploadAutoPastePrefsKey,
  fallback: false,
);
