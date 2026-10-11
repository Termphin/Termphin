import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/platform_info.dart';

const kDownloadFolderUriPrefsKey = 'download_folder_uri';
const kDownloadFolderLabelPrefsKey = 'download_folder_label';

/// A folder the user picked through the Android document picker, held as a
/// persisted tree URI. Nothing but the URI is stored - a path would be
/// meaningless on Android 11+, where the app has no filesystem access to
/// anything outside its own sandbox.
class DownloadFolder {
  const DownloadFolder({required this.uri, required this.label});

  final String uri;

  /// What the picker calls the folder, so Settings can name it without
  /// re-deriving anything from the URI.
  final String label;
}

/// Where SFTP downloads land. Unset means the platform Downloads folder, which
/// needs no permission on any Android this app supports.
class DownloadLocation {
  DownloadLocation._();

  static final instance = DownloadLocation._();

  static const _channel = MethodChannel('dev.termphin.termphin/downloads');

  DownloadFolder? _folder;
  bool _loaded = false;

  /// The chosen folder, or null for the system Downloads folder. The stored
  /// grant is verified once per launch: the user can revoke it from system
  /// settings, and a folder that cannot be written to any more is worse than
  /// no setting at all.
  Future<DownloadFolder?> current() async {
    if (_loaded) return _folder;
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(kDownloadFolderUriPrefsKey);
    _loaded = true;
    if (uri == null) return _folder = null;
    if (!await _hasAccess(uri)) {
      await prefs.remove(kDownloadFolderUriPrefsKey);
      await prefs.remove(kDownloadFolderLabelPrefsKey);
      return _folder = null;
    }
    return _folder = DownloadFolder(
      uri: uri,
      label: prefs.getString(kDownloadFolderLabelPrefsKey) ?? '',
    );
  }

  /// Opens the system folder picker. Returns null when the user backs out.
  Future<DownloadFolder?> pick() async {
    if (!isAndroidPlatform) return null;
    final result = await _channel.invokeMapMethod<String, String>(
      'pickDownloadFolder',
    );
    if (result == null) return null;
    final folder = DownloadFolder(
      uri: result['uri']!,
      label: result['label'] ?? '',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kDownloadFolderUriPrefsKey, folder.uri);
    await prefs.setString(kDownloadFolderLabelPrefsKey, folder.label);
    _folder = folder;
    _loaded = true;
    return folder;
  }

  /// Back to the system Downloads folder, handing the grant back so the folder
  /// stops showing up in the app's persisted permissions. Nothing is left to
  /// release when the platform refuses the call.
  Future<void> clear() async {
    final folder = _folder ?? await current();
    if (folder != null && isAndroidPlatform) {
      try {
        await _channel.invokeMethod('releaseDownloadFolder', {
          'treeUri': folder.uri,
        });
      } on PlatformException catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kDownloadFolderUriPrefsKey);
    await prefs.remove(kDownloadFolderLabelPrefsKey);
    _folder = null;
    _loaded = true;
  }

  /// Drops a setting the platform no longer honours - called when a save comes
  /// back saying the grant is gone, so the next download uses Downloads instead
  /// of failing the same way.
  Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kDownloadFolderUriPrefsKey);
    await prefs.remove(kDownloadFolderLabelPrefsKey);
    _folder = null;
    _loaded = true;
  }

  /// Drops the cached lookup so the next call re-reads preferences.
  @visibleForTesting
  void invalidateCache() {
    _loaded = false;
    _folder = null;
  }

  Future<bool> _hasAccess(String uri) async {
    if (!isAndroidPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('hasDownloadFolderAccess', {
            'treeUri': uri,
          }) ??
          false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
