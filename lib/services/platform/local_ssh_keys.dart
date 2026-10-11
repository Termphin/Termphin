import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/ssh_key.dart';
import '../../utils/platform_info.dart';
import '../storage/ssh_key_storage.dart';

/// A private key found in the user's own `.ssh` folder, not yet in the app.
class LocalSshKey {
  const LocalSshKey({
    required this.name,
    required this.displayPath,
    required this.pem,
    required this.encrypted,
    this.publicKeyBlob,
    this.algorithm,
  });

  /// The file's name, which is what the key is called once imported.
  final String name;

  /// Where it is, written from the home folder - `~/.ssh/id_ed25519` - so
  /// it never spells out the user's name.
  final String displayPath;
  final String pem;

  /// Whether importing it needs its passphrase.
  final bool encrypted;

  /// The base64 middle of the `.pub` beside it, when there is one: the only
  /// way to tell an encrypted key is already imported without unlocking it.
  final String? publicKeyBlob;

  /// What kind of key it is, as OpenSSH names it without the prefix -
  /// `ed25519`, `rsa`, `ecdsa` - read off the `.pub` beside it or, failing
  /// that, an old-style PEM header. Null when neither says.
  final String? algorithm;
}

/// Finds the private keys in `~/.ssh`, so a desktop user's existing keys are
/// one click from being usable instead of a file picker and a paste away.
///
/// The folder is the same on all three systems: OpenSSH keeps it in the home
/// folder, which is `HOME` on Linux and a Mac and `USERPROFILE` on Windows.
/// A sandboxed Mac build is handed a container for `HOME`; the real folder
/// is worked out from the user's name, and reading it then succeeds only if
/// the sandbox lets it - when it does not, nothing is found and the section
/// simply is not there.
///
/// Nothing is read but what looks like a key: small files that open with a
/// PEM private-key header. `known_hosts`, `config` and the `.pub` halves are
/// never candidates.
class LocalSshKeys {
  LocalSshKeys({Directory? directory, Map<String, String>? environment})
    : _directory = directory,
      _environment = environment ?? Platform.environment;

  final Directory? _directory;
  final Map<String, String> _environment;

  /// A private key is a few kilobytes; anything past this is something else
  /// that happens to live in the folder.
  static const int _maxKeyBytes = 64 * 1024;

  static const _skippedNames = {'config', 'authorized_keys', 'environment'};

  /// The home folder as the system names it, or null where it is not told.
  String? get _home {
    if (isWindowsPlatform) return _environment['USERPROFILE'];
    final home = _environment['HOME'];
    final user = _environment['USER'];
    if (isMacOSPlatform &&
        home != null &&
        user != null &&
        home.contains('/Library/Containers/')) {
      return '/Users/$user';
    }
    return home;
  }

  Directory? get directory {
    if (_directory != null) return _directory;
    final home = _home;
    if (home == null || home.isEmpty) return null;
    return Directory('$home${Platform.pathSeparator}.ssh');
  }

  /// The keys in the folder that are not among [imported], by name.
  ///
  /// A folder that is missing or cannot be read is an empty list, as is a
  /// file that cannot be: there is nothing the user could do about either
  /// from here, and nothing they asked for has failed.
  Future<List<LocalSshKey>> scan({List<SshKey> imported = const []}) async {
    final folder = directory;
    if (folder == null) return const [];
    final importedBlobs = {
      for (final key in imported) ?_blobOf(key.publicKeyOpenSSH),
    };
    final importedPems = {for (final key in imported) key.privateKeyPem.trim()};
    final found = <LocalSshKey>[];
    try {
      if (!await folder.exists()) return const [];
      await for (final entity in folder.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.endsWith('.pub') ||
            name.startsWith('known_hosts') ||
            _skippedNames.contains(name)) {
          continue;
        }
        final key = await _read(entity, name);
        if (key == null) continue;
        if (importedPems.contains(key.pem)) continue;
        if (key.publicKeyBlob != null &&
            importedBlobs.contains(key.publicKeyBlob)) {
          continue;
        }
        found.add(key);
      }
    } on FileSystemException {
      return const [];
    }
    found.sort((a, b) => a.name.compareTo(b.name));
    return found;
  }

  Future<LocalSshKey?> _read(File file, String name) async {
    try {
      if (await file.length() > _maxKeyBytes) return null;
      final pem = (await file.readAsString()).trim();
      if (!pem.startsWith('-----BEGIN ') || !pem.contains('PRIVATE KEY-----')) {
        return null;
      }
      String? blob;
      String? algorithm = _algorithmOfPem(pem);
      final public = File('${file.path}.pub');
      if (await public.exists()) {
        final line = await public.readAsString();
        blob = _blobOf(line);
        algorithm = _algorithmOfPublic(line) ?? algorithm;
      }
      return LocalSshKey(
        name: name,
        displayPath: '~/.ssh/$name',
        pem: pem,
        encrypted: SshKeyStorage.isEncryptedPem(pem),
        publicKeyBlob: blob,
        algorithm: algorithm,
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// `ssh-ed25519` and `ecdsa-sha2-nistp256` as `ed25519` and `ecdsa`.
  static String? _algorithmOfPublic(String publicKey) {
    final type = publicKey.trim().split(RegExp(r'\s+')).first;
    if (type.isEmpty) return null;
    final name = type.startsWith('ssh-') ? type.substring(4) : type;
    return name.split('-').first.toLowerCase();
  }

  /// Only the old PEM formats name the algorithm in their header; an
  /// `OPENSSH PRIVATE KEY` keeps it inside.
  static String? _algorithmOfPem(String pem) {
    final header = pem.split('\n').first;
    if (header.contains('RSA')) return 'rsa';
    if (header.contains('EC ')) return 'ecdsa';
    if (header.contains('DSA')) return 'dsa';
    return null;
  }

  /// The key itself out of an OpenSSH public key line: `type blob comment`.
  static String? _blobOf(String publicKey) {
    final parts = publicKey.trim().split(RegExp(r'\s+'));
    return parts.length >= 2 ? parts[1] : null;
  }
}

final localSshKeysProvider = Provider<LocalSshKeys>((ref) => LocalSshKeys());
