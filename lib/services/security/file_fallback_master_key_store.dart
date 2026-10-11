import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'secret_cipher.dart';

/// The master key on a Linux desktop: in the Secret Service keyring when the
/// session has one, in a file only the user can read when it does not.
///
/// A desktop session without a keyring is common - a tiling window manager
/// started without gnome-keyring or KeePassXC has no Secret Service at all -
/// and there the keyring cannot be written to either, so every password and
/// key the user saved failed to seal. The file is what Chromium and VS Code
/// fall back to in the same place: the secrets are then protected by the
/// file's permissions rather than by the keyring, which is weaker, and
/// [usingFile] is there for Settings to say so.
///
/// The keyring wins whenever it answers. A key found in the file while the
/// keyring has none is moved into the keyring and the file deleted, so a user
/// who installs one later is not left on the file for good; a keyring that
/// already holds a key leaves a stray file alone rather than guess which of the
/// two the sealed secrets were written under.
class FileFallbackMasterKeyStore implements MasterKeyStore {
  FileFallbackMasterKeyStore({
    MasterKeyStore primary = const KeystoreMasterKeyStore(),
    Future<File> Function()? keyFile,
  }) : _primary = primary,
       _keyFile = keyFile ?? _defaultKeyFile;

  final MasterKeyStore _primary;
  final Future<File> Function() _keyFile;

  /// Whether the key lives in the file - Settings warns while it does.
  static final usingFile = ValueNotifier<bool>(false);

  static Future<File> _defaultKeyFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/master_key');
  }

  /// A key still in the file is moved into the keyring once it can hold it -
  /// moved, not copied: from then on the file would only be a weaker second
  /// copy of the same key.
  @override
  Future<String?> read() async {
    final String? fromKeyring;
    try {
      fromKeyring = await _primary.read();
    } catch (error) {
      debugPrint('[MasterKey] No keyring to read from, using the file: $error');
      usingFile.value = true;
      return _readFile();
    }
    usingFile.value = false;
    if (fromKeyring != null) return fromKeyring;

    final fromFile = await _readFile();
    if (fromFile == null) return null;
    try {
      await _primary.write(fromFile);
      await (await _keyFile()).delete();
    } catch (_) {
      usingFile.value = true;
    }
    return fromFile;
  }

  @override
  Future<void> write(String value) async {
    if (!usingFile.value) {
      try {
        await _primary.write(value);
        return;
      } catch (error) {
        debugPrint(
          '[MasterKey] No keyring to write to, using the file: '
          '$error',
        );
        usingFile.value = true;
      }
    }
    await _writeFile(value);
  }

  Future<String?> _readFile() async {
    final file = await _keyFile();
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  /// Created empty and made owner-only before the key goes in, so there is no
  /// moment at which the key sits in a file the umask left world-readable.
  Future<void> _writeFile(String value) async {
    final file = await _keyFile();
    await file.parent.create(recursive: true);
    if (!await file.exists()) await file.create();
    final chmod = await Process.run('chmod', ['600', file.path]);
    if (chmod.exitCode != 0) {
      throw FileSystemException(
        'Could not make the key file private',
        file.path,
      );
    }
    await file.writeAsString(value, flush: true);
  }
}
