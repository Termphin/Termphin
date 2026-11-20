import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../security/aead.dart';
import '../security/secret_cipher.dart';
import '../ssh/remote_agent_service.dart'
    show powerShellCommandLine, shellQuote;

/// Where the agent reports presence. Overridable at build time for staging.
const kPresenceUrl = String.fromEnvironment(
  'TERMPHIN_PRESENCE_URL',
  defaultValue: 'https://rt.termphin.dev',
);

const _storeKey = 'presence_keys';
const _storeAad = 'presence_keys';

/// The keys that open each server's presence state, by profile id.
///
/// A server's key is made by the first device that sets it up and kept in
/// `~/.config/termphin/presence` there; every device that connects reads it
/// back and keeps it here, sealed like the rest of the app's secrets. That
/// way any of the user's devices with SSH access to a server can read its
/// sessions, and neither the backend nor Firebase ever holds the key.
class PresenceKeyStore {
  PresenceKeyStore({SecretCipher? cipher})
    : _cipher = cipher ?? SecretCipher.instance;

  final SecretCipher _cipher;
  Map<String, Uint8List>? _keys;

  /// Notified whenever a key is added or replaced.
  final changes = ValueNotifier<int>(0);

  Future<Uint8List?> keyFor(String profileId) async =>
      (await _load())[profileId];

  Future<void> remember(String profileId, Uint8List key) async {
    final keys = await _load();
    final existing = keys[profileId];
    if (existing != null && listEquals(existing, key)) return;
    keys[profileId] = key;
    final encoded = jsonEncode({
      for (final entry in keys.entries)
        entry.key: base64Url.encode(entry.value),
    });
    await (await SharedPreferences.getInstance()).setString(
      _storeKey,
      await _cipher.seal(encoded, aad: _storeAad),
    );
    changes.value++;
  }

  Future<Map<String, Uint8List>> _load() async {
    final cached = _keys;
    if (cached != null) return cached;
    final keys = <String, Uint8List>{};
    final stored = (await SharedPreferences.getInstance()).getString(_storeKey);
    if (stored != null) {
      final opened = await _cipher.open(stored, aad: _storeAad);
      if (opened != null) {
        try {
          final decoded = jsonDecode(opened) as Map<String, dynamic>;
          for (final entry in decoded.entries) {
            final key = base64Url.decode(entry.value as String);
            if (key.length == 32) keys[entry.key] = key;
          }
        } catch (_) {}
      }
    }
    return _keys = keys;
  }
}

/// The keys this device holds for opening servers' presence state.
final presenceKeys = PresenceKeyStore();

/// A fresh 32-byte presence key.
Uint8List newPresenceKey() => randomBytes(32);

/// URL-safe base64 without padding: how the key is written on the server.
String encodePresenceKey(Uint8List key) =>
    base64Url.encode(key).replaceAll('=', '');

/// Writes `<url> <key>` to the server's presence file unless one is already
/// there, then prints the key the file holds - the one this command wrote,
/// or the one another device wrote before. Created readable by its owner
/// only. Both values are URL-safe, so single quotes are all the quoting they
/// need.
String presenceKeyCommand(String url, String key) =>
    "umask 077 && mkdir -p ~/.config/termphin && "
    "f=~/.config/termphin/presence && "
    "{ [ -s \"\$f\" ] || printf '%s %s\\n' '$url' '$key' > \"\$f\"; } && "
    "cut -d' ' -f2 \"\$f\"";

/// The Windows twin of [presenceKeyCommand], restricted to the current user
/// with icacls like the relay file.
String presenceKeyCommandWindows(String url, String key) =>
    powerShellCommandLine(
      r'''
$ProgressPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.config\termphin'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$file = Join-Path $dir 'presence'
$current = if (Test-Path -LiteralPath $file) { (Get-Content -LiteralPath $file -Raw -ErrorAction SilentlyContinue) } else { '' }
if (-not $current -or -not $current.Trim()) {
  Set-Content -Path $file -Value '''
      "'$url $key'"
      r''' -NoNewline -Encoding ascii
  icacls $file /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
  $current = Get-Content -LiteralPath $file -Raw
}
$fields = $current.Trim() -split ' '
if ($fields.Count -ge 2) { $fields[1] }
''',
    );

final _keyLine = RegExp(r'^[A-Za-z0-9_-]{43}=?$');

/// The 32-byte key in [output] of a presence key command, read line by line
/// because the output carries stderr too; null when no line holds one.
Uint8List? parsePresenceKey(String output) {
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final candidate = line.trim();
    if (!_keyLine.hasMatch(candidate)) continue;
    try {
      final key = base64Url.decode(base64Url.normalize(candidate));
      if (key.length == 32) return key;
    } catch (_) {}
  }
  return null;
}

/// Marks the crontab lines the app owns, so it can find and remove exactly
/// those and nothing of the user's.
const presenceCronTag = '# termphin-presence';

const _presenceCronInstall = r'''
command -v crontab >/dev/null 2>&1 || exit 0
bin="$HOME/.local/lib/termphin/termphin-agent"
current=$(crontab -l 2>&1)
status=$?
if [ "$status" -ne 0 ]; then
  case "$current" in *"no crontab"*) current="" ;; *) exit 0 ;; esac
fi
case "$current" in *"# termphin-presence"*) exit 0 ;; esac
{
  [ -n "$current" ] && printf '%s\n' "$current"
  printf '%s\n' "*/5 * * * * \"$bin\" presence >/dev/null 2>&1 # termphin-presence"
  printf '%s\n' "@reboot sleep 60 && \"$bin\" presence >/dev/null 2>&1 # termphin-presence"
} | crontab -
''';

const _presenceCronRemove = r'''
command -v crontab >/dev/null 2>&1 || exit 0
current=$(crontab -l 2>/dev/null) || exit 0
case "$current" in *"# termphin-presence"*) ;; *) exit 0 ;; esac
printf '%s\n' "$current" | grep -v '# termphin-presence' | crontab -
''';

/// Adds the two crontab lines that keep a machine with no session online:
/// `termphin-agent presence` every five minutes and a minute after boot.
///
/// Never at the cost of what is there: the current crontab is read first and
/// written back with the lines appended, and when it cannot be read - for
/// any reason other than there being none - nothing is written. Lines
/// already in place are left alone. Run through `sh`, so the user's own shell
/// does not matter; a server without `crontab` is skipped.
String presenceCronInstallCommand() =>
    'sh -c ${shellQuote(_presenceCronInstall)}';

/// Removes the lines [presenceCronInstallCommand] added and nothing else.
String presenceCronRemoveCommand() =>
    'sh -c ${shellQuote(_presenceCronRemove)}';
