import 'dart:convert';
import 'dart:io';

import '../storage/ssh_key_storage.dart';

/// One `Host` of an OpenSSH client config, with what ssh would use for it.
class SshConfigHost {
  const SshConfigHost({
    required this.alias,
    required this.hostName,
    required this.port,
    this.user,
    this.identityFile,
  });

  /// The name after `Host` - what is typed after `ssh`.
  final String alias;
  final String hostName;
  final int port;
  final String? user;

  /// As written, `~` and all; null when the config names none.
  final String? identityFile;
}

/// Why a host from the config cannot be brought in as it stands.
enum SshConfigProblem {
  /// No `IdentityFile` and none of ssh's default keys on disk - it signs in
  /// with a password, which the config never holds.
  noKey,

  /// The key is passphrase-protected; the passphrase is asked for in the
  /// machine form, not here.
  encryptedKey,

  /// The key file is missing, too large, or not text.
  unreadableKey,

  /// A machine with this address and user is already in the list.
  alreadyAdded,
}

/// A host from the config together with the key it signs in with.
class SshConfigCandidate {
  const SshConfigCandidate({
    required this.host,
    required this.username,
    this.keyPath,
    this.keyPem,
    this.problem,
  });

  final SshConfigHost host;

  /// The config's `User`, or the local account as ssh itself falls back to.
  final String username;
  final String? keyPath;
  final String? keyPem;
  final SshConfigProblem? problem;

  bool get importable => problem == null;
}

/// The keys ssh tries when the config names none, in its order.
const kDefaultIdentityFiles = ['id_ed25519', 'id_ecdsa', 'id_rsa'];

const _maxKeyBytes = 1024 * 1024;

/// Reads an OpenSSH client config the way ssh does: for each host named
/// outright, every block whose pattern matches it is walked in file order and
/// the first value found for a keyword wins. Lines before the first `Host`
/// apply to every host.
///
/// Only what a machine here has a field for is read - `HostName`, `User`,
/// `Port`, `IdentityFile`. A `Host` that is only a pattern (`*`, `*.lan`) is
/// not a machine and lends its values to the others; `Match` blocks and
/// `Include` are stepped over.
List<SshConfigHost> parseSshConfig(String text) {
  final blocks = <_Block>[
    _Block(const ['*']),
  ];
  var skipping = false;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = RegExp(r'^(\S+?)(?:\s*=\s*|\s+)(.*)$').firstMatch(line);
    if (match == null) continue;
    final keyword = match.group(1)!.toLowerCase();
    final value = _unquote(match.group(2)!.trim());
    if (keyword == 'match') {
      skipping = true;
      continue;
    }
    if (keyword == 'host') {
      skipping = false;
      blocks.add(_Block(value.split(RegExp(r'\s+'))));
      continue;
    }
    if (skipping) continue;
    blocks.last.values.putIfAbsent(keyword, () => value);
  }

  final hosts = <SshConfigHost>[];
  final seen = <String>{};
  for (final block in blocks.skip(1)) {
    for (final alias in block.patterns) {
      if (_isPattern(alias) || !seen.add(alias)) continue;
      String? value(String keyword) {
        for (final other in blocks) {
          if (other.matches(alias)) {
            final found = other.values[keyword];
            if (found != null) return found;
          }
        }
        return null;
      }

      final port = int.tryParse(value('port') ?? '');
      hosts.add(
        SshConfigHost(
          alias: alias,
          hostName: (value('hostname') ?? alias).replaceAll('%h', alias),
          port: port != null && port > 0 && port < 65536 ? port : 22,
          user: value('user'),
          identityFile: value('identityfile'),
        ),
      );
    }
  }
  return hosts;
}

class _Block {
  _Block(this.patterns);

  final List<String> patterns;
  final values = <String, String>{};

  /// As ssh: any positive pattern matching, and no negated one.
  bool matches(String alias) {
    var matched = false;
    for (final pattern in patterns) {
      if (pattern.startsWith('!')) {
        if (_glob(pattern.substring(1)).hasMatch(alias)) return false;
      } else if (_glob(pattern).hasMatch(alias)) {
        matched = true;
      }
    }
    return matched;
  }
}

bool _isPattern(String host) =>
    host.contains('*') || host.contains('?') || host.startsWith('!');

RegExp _glob(String pattern) => RegExp(
  '^${pattern.split('').map((c) => switch (c) {
    '*' => '.*',
    '?' => '.',
    _ => RegExp.escape(c),
  }).join()}\$',
);

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

/// The user's home, where `~/.ssh` is; null where there is none to read.
String? sshHomeDirectory() {
  final env = Platform.environment;
  final home = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
  return home == null || home.isEmpty ? null : home;
}

/// The hosts in `~/.ssh/config`, each with the key ssh would sign in with
/// read off disk. Empty when there is no config.
///
/// [existing] are the `user@host:port` of machines already in the list, so a
/// second run does not offer them again.
Future<List<SshConfigCandidate>> readSshConfigCandidates({
  required String home,
  Set<String> existing = const {},
  String? localUser,
}) async {
  final separator = Platform.pathSeparator;
  final sshDir = '$home$separator.ssh';
  final config = File('$sshDir${separator}config');
  if (!await config.exists()) return const [];
  final String text;
  try {
    text = await config.readAsString();
  } on Object {
    return const [];
  }
  final fallbackUser =
      localUser ??
      Platform.environment['USER'] ??
      Platform.environment['USERNAME'] ??
      '';

  final keys = <String, (String?, SshConfigProblem?)>{};
  Future<(String?, SshConfigProblem?)> readKey(String path) async =>
      keys[path] ??= await _readKey(path);

  final candidates = <SshConfigCandidate>[];
  for (final host in parseSshConfig(text)) {
    final username = host.user ?? fallbackUser;
    String? keyPath;
    if (host.identityFile case final named?) {
      keyPath = _expand(named, home: home, sshDir: sshDir);
    } else {
      for (final name in kDefaultIdentityFiles) {
        final path = '$sshDir$separator$name';
        if (await File(path).exists()) {
          keyPath = path;
          break;
        }
      }
    }
    String? pem;
    SshConfigProblem? problem;
    if (existing.contains(
      sshConfigIdentity(username, host.hostName, host.port),
    )) {
      problem = SshConfigProblem.alreadyAdded;
    } else if (keyPath == null) {
      problem = SshConfigProblem.noKey;
    } else {
      (pem, problem) = await readKey(keyPath);
    }
    candidates.add(
      SshConfigCandidate(
        host: host,
        username: username,
        keyPath: keyPath,
        keyPem: pem,
        problem: problem,
      ),
    );
  }
  return candidates;
}

/// What makes two machines the same one for [readSshConfigCandidates].
String sshConfigIdentity(String username, String host, int port) =>
    '$username@${host.toLowerCase()}:$port';

Future<(String?, SshConfigProblem?)> _readKey(String path) async {
  try {
    final file = File(path);
    if (!await file.exists() || await file.length() > _maxKeyBytes) {
      return (null, SshConfigProblem.unreadableKey);
    }
    final pem = (await file.readAsString()).trim();
    if (pem.isEmpty) return (null, SshConfigProblem.unreadableKey);
    if (SshKeyStorage.isEncryptedPem(pem)) {
      return (null, SshConfigProblem.encryptedKey);
    }
    return (pem, null);
  } on Object {
    return (null, SshConfigProblem.unreadableKey);
  }
}

/// `~` and `%d` are the home directory; a bare name is looked for in `~/.ssh`.
String _expand(String path, {required String home, required String sshDir}) {
  final separator = Platform.pathSeparator;
  var expanded = path.replaceAll('%d', home);
  if (expanded == '~') return home;
  if (expanded.startsWith('~/') || expanded.startsWith('~\\')) {
    expanded = '$home$separator${expanded.substring(2)}';
  }
  final absolute =
      expanded.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(expanded);
  return absolute ? expanded : '$sshDir$separator$expanded';
}
