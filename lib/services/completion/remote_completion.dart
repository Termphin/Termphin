import 'dart:convert';
import 'dart:typed_data';

import '../ssh/remote_agent_service.dart' show powerShellCommandLine;

/// Which shell answers "what could come next" on a host.
enum CompletionEngine { none, bash, fish, powershell }

/// What a host offers for completion, read once per connection.
class HostCompletionData {
  HostCompletionData({
    required List<String> history,
    required this.commands,
    required this.engine,
    this.bashCompletionPath,
  }) : history = [...history];

  /// Oldest first. Grows with what is typed in this app, since bash writes its
  /// history file only when the shell exits.
  final List<String> history;

  final Set<String> commands;

  final CompletionEngine engine;

  /// The bash-completion script to source, when the host has one.
  final String? bashCompletionPath;

  /// A fresh one each time: [remember] adds to it.
  static HostCompletionData get empty => HostCompletionData(
    history: const [],
    commands: const {},
    engine: CompletionEngine.none,
  );

  void remember(String command) {
    if (looksSecret(command)) return;
    history.add(command);
    if (history.length > _kMaxHistory) {
      history.removeRange(0, history.length - _kMaxHistory);
    }
  }
}

const _kMaxHistory = 5000;

const _kMarker = '@@termphin:';

final _secretAssignment = RegExp(
  r'(pass(word|wd)?|token|secret|api[_-]?key|auth)\s*[=:]',
  caseSensitive: false,
);

final _inlinePassword = RegExp(r'\b(mysql|mariadb|mysqldump)\b.*\s-p\S');

/// A command that should neither be suggested nor kept: one the user hid from
/// history with a leading space, or one carrying a credential inline.
bool looksSecret(String command) =>
    command.startsWith(' ') ||
    command.contains('sshpass') ||
    _secretAssignment.hasMatch(command) ||
    _inlinePassword.hasMatch(command);

/// Runs [script] under `sh` whatever the login shell is: base64 needs no
/// quoting in sh, bash, zsh or fish alike.
String wrapForAnyShell(String script) =>
    'echo ${base64.encode(utf8.encode(script))} | base64 -d | sh';

String _b64(String value) => base64.encode(utf8.encode(value));

const _bashCompletionCandidates = [
  '/usr/share/bash-completion/bash_completion',
  '/etc/bash_completion',
  '/usr/local/share/bash-completion/bash_completion',
  '/opt/homebrew/share/bash-completion/bash_completion',
  '/usr/local/etc/bash_completion',
];

/// Lists the host's shells, history files and commands on PATH, in sections
/// [parseProbe] reads back.
String probeCommand() => wrapForAnyShell('''
exec 2>/dev/null
echo "${_kMarker}shell \${SHELL##*/}"
command -v bash >/dev/null && echo "${_kMarker}has bash"
command -v fish >/dev/null && echo "${_kMarker}has fish"
for f in ${_bashCompletionCandidates.join(' ')}; do
  if [ -r "\$f" ]; then echo "${_kMarker}bashcomp \$f"; break; fi
done
for f in "\$HOME/.bash_history" "\$HOME/.zsh_history" "\$HOME/.local/share/fish/fish_history"; do
  [ -r "\$f" ] || continue
  echo "${_kMarker}history \${f##*/}"
  tail -n 3000 "\$f"
  echo
done
echo "${_kMarker}commands"
IFS=:
for d in \$PATH; do [ -d "\$d" ] && ls -1 "\$d"; done | sort -u
''');

/// [probeCommand] for Windows: PSReadLine's history, and every cmdlet,
/// function, alias and program on PATH - a program by the name it is run
/// with, without its extension.
String powerShellProbeCommand() => powerShellCommandLine(r'''
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
'@@termphin:shell powershell'
$h = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
if (Test-Path -LiteralPath $h) {
  '@@termphin:history ConsoleHost_history.txt'
  Get-Content -LiteralPath $h -Tail 3000 -Encoding UTF8
}
'@@termphin:commands'
Get-Command -CommandType Alias, Function, Cmdlet | ForEach-Object Name
$ext = $env:PATHEXT -split ';' | Where-Object { $_ }
Get-Command -CommandType Application |
  Where-Object { $ext -contains $_.Extension } |
  ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) }
''');

/// Turns [probeCommand] or [powerShellProbeCommand]'s output into
/// [HostCompletionData].
///
/// Files carry no common clock, so the login shell's own history goes last
/// in the merged list: that is where what was run most recently is.
HostCompletionData parseProbe(Uint8List output) {
  String? shell;
  var hasBash = false;
  var hasFish = false;
  String? bashCompletionPath;
  final histories = <String, List<String>>{};
  final commands = <String>{};

  String? section;
  String? historyFile;
  for (final raw in _splitLines(output)) {
    var line = utf8.decode(
      historyFile == '.zsh_history' ? _unmetafy(raw) : raw,
      allowMalformed: true,
    );
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (_isPowerShellNoise(line)) continue;
    if (line.startsWith(_kMarker)) {
      final rest = line.substring(_kMarker.length);
      final space = rest.indexOf(' ');
      final key = space < 0 ? rest : rest.substring(0, space);
      final value = space < 0 ? '' : rest.substring(space + 1).trim();
      section = key;
      historyFile = null;
      switch (key) {
        case 'shell':
          shell = value;
        case 'has':
          if (value == 'bash') hasBash = true;
          if (value == 'fish') hasFish = true;
        case 'bashcomp':
          bashCompletionPath = value;
        case 'history':
          historyFile = value;
      }
      continue;
    }
    switch (section) {
      case 'history':
        final command = _historyEntry(line, historyFile);
        if (command != null && !looksSecret(command)) {
          (histories[historyFile ?? ''] ??= []).add(command);
        }
      case 'commands':
        final name = line.trim();
        if (name.isNotEmpty && !name.contains('/')) commands.add(name);
    }
  }

  final engine = shell == 'powershell'
      ? CompletionEngine.powershell
      : shell == 'fish' && hasFish
      ? CompletionEngine.fish
      : hasBash
      ? CompletionEngine.bash
      : hasFish
      ? CompletionEngine.fish
      : CompletionEngine.none;
  final ownFile = switch (shell) {
    'zsh' => '.zsh_history',
    'fish' => 'fish_history',
    'powershell' => 'ConsoleHost_history.txt',
    _ => '.bash_history',
  };
  final history = [
    for (final entry in histories.entries)
      if (entry.key != ownFile) ...entry.value,
    ...?histories[ownFile],
  ];
  return HostCompletionData(
    history: history,
    commands: commands,
    engine: engine,
    bashCompletionPath: bashCompletionPath,
  );
}

/// One history file line as a command, or null for a line that is not one:
/// bash's `#1700000000` timestamps, zsh's `: 1700000000:0;` prefix, fish's
/// YAML-ish `- cmd:` records.
String? _historyEntry(String line, String? file) {
  switch (file) {
    case '.zsh_history':
      final m = RegExp(r'^: \d+:\d+;(.*)$').firstMatch(line);
      line = m != null ? m.group(1)! : line;
    case 'fish_history':
      if (!line.startsWith('- cmd: ')) return null;
      line = line
          .substring('- cmd: '.length)
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\\', r'\');
    default:
      if (RegExp(r'^#\d+$').hasMatch(line)) return null;
  }
  final command = line.trimRight();
  return command.trim().isEmpty ? null : command;
}

Iterable<Uint8List> _splitLines(Uint8List bytes) sync* {
  var start = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0x0a) {
      yield Uint8List.sublistView(bytes, start, i);
      start = i + 1;
    }
  }
  if (start < bytes.length) yield Uint8List.sublistView(bytes, start);
}

/// zsh writes bytes above 0x83 into its history escaped as 0x83 followed by
/// the byte xor 0x20.
Uint8List _unmetafy(Uint8List bytes) {
  if (!bytes.contains(0x83)) return bytes;
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0x83 && i + 1 < bytes.length) {
      out.addByte(bytes[++i] ^ 0x20);
    } else {
      out.addByte(bytes[i]);
    }
  }
  return out.toBytes();
}

/// Asks the host's own completion for every candidate for the last word of
/// [line], run in the directory the session's shell is in.
///
/// [cwdFile] is where the agent keeps that directory, relative to home; a
/// plain session has none and completes from home.
String completeCommand(
  CompletionEngine engine,
  String line, {
  String? cwdFile,
  String? directory,
  String? bashCompletionPath,
}) {
  if (engine == CompletionEngine.powershell) {
    return _powerShellComplete(line, directory);
  }
  final inner = switch (engine) {
    CompletionEngine.bash => ('bash', _bashScript(bashCompletionPath)),
    CompletionEngine.fish => ('fish', _fishScript),
    CompletionEngine.none ||
    CompletionEngine.powershell => throw ArgumentError('No sh engine.'),
  };
  return wrapForAnyShell('''
exec 2>/dev/null
TERMPHIN_LINE=\$(printf %s '${_b64(line)}' | base64 -d)
TERMPHIN_DIR=
${cwdFile == null ? '' : 'TERMPHIN_DIR=\$(cat "\$HOME/\$(printf %s \'${_b64(cwdFile)}\' | base64 -d)")'}
export TERMPHIN_LINE TERMPHIN_DIR
s=\$(printf %s '${_b64(inner.$2)}' | base64 -d)
if command -v timeout >/dev/null; then exec timeout 3 ${inner.$1} -c "\$s"; fi
exec ${inner.$1} -c "\$s"
''');
}

String _bashScript(String? completionPath) =>
    '''
exec 2>/dev/null
[ -n "\$TERMPHIN_DIR" ] && cd -- "\$TERMPHIN_DIR"
PS1='\$ '
${completionPath == null ? '' : '. ${_shQuote(completionPath)}'}
line=\$TERMPHIN_LINE
read -ra COMP_WORDS <<< "\$line"
[[ -z \$line || \$line == *[[:space:]] ]] && COMP_WORDS+=("")
COMP_CWORD=\$(( \${#COMP_WORDS[@]} - 1 ))
COMP_LINE=\$line
COMP_POINT=\${#line}
COMP_TYPE=9
COMP_KEY=9
cur=\${COMP_WORDS[COMP_CWORD]}
prev=\${COMP_WORDS[COMP_CWORD-1]}
cmd=\${COMP_WORDS[0]}
COMPREPLY=()
spec=\$(complete -p -- "\$cmd")
if [[ -z \$spec ]] && declare -F _comp_load >/dev/null; then _comp_load -- "\$cmd"; spec=\$(complete -p -- "\$cmd"); fi
if [[ -z \$spec ]] && declare -F _completion_loader >/dev/null; then _completion_loader "\$cmd"; spec=\$(complete -p -- "\$cmd"); fi
if [[ \$spec =~ \\ -F\\ ([^ ]+) ]]; then
  "\${BASH_REMATCH[1]}" "\$cmd" "\$cur" "\$prev"
elif [[ -n \$spec ]]; then
  opts=\${spec#complete }
  opts=\${opts% *}
  eval "mapfile -t COMPREPLY < <(compgen \$opts -- \\"\\\$cur\\")"
fi
(( \${#COMPREPLY[@]} )) || mapfile -t COMPREPLY < <(compgen -f -- "\$cur")
for c in "\${COMPREPLY[@]}"; do
  [[ -d \$c && \$c != */ ]] && c="\$c/"
  printf '%s\\n' "\$c"
done | head -n 500
''';

const _fishScript = r'''
test -n "$TERMPHIN_DIR"; and cd $TERMPHIN_DIR
complete -C "$TERMPHIN_LINE" | head -n 500
''';

/// PowerShell's own completion, `TabExpansion2`. [directory] is where the
/// shell is, as its prompt last reported it; without one, home.
///
/// Its answers are reshaped to what was typed: a file here comes back as
/// `.\name`, and a path typed with `/` comes back with `\`.
String _powerShellComplete(String line, String? directory) =>
    powerShellCommandLine(
      _powerShellCompleteScript
          .replaceFirst('@@DIR@@', _psQuote(directory ?? ''))
          .replaceFirst('@@LINE@@', _psQuote(line)),
    );

const _powerShellCompleteScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$line = @@LINE@@
$dir = @@DIR@@
if ($dir) { Set-Location -LiteralPath $dir }
$word = ($line -split '\s')[-1]
$slash = $word.Contains('/')
$r = TabExpansion2 -inputScript $line -cursorColumn $line.Length
foreach ($m in ($r.CompletionMatches | Select-Object -First 500)) {
  $c = $m.CompletionText
  if ($c.StartsWith('.\') -and -not ($word.StartsWith('.\') -or $word.StartsWith('./'))) {
    $c = $c.Substring(2)
  }
  if ($slash) { $c = $c.Replace('\', '/') }
  if ($m.ResultType -eq 'ProviderContainer' -and
      -not ($c.EndsWith('\') -or $c.EndsWith('/') -or $c.EndsWith("'"))) {
    if ($slash) { $c += '/' } else { $c += '\' }
  }
  $c
}
''';

/// A PowerShell literal. It takes the typographic single quotes for quotes
/// too, so those are doubled as well.
String _psQuote(String value) =>
    "'${value.replaceAllMapped(RegExp("['‘’‚‛]"), (m) => '${m[0]}${m[0]}')}'";

String _shQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// Windows PowerShell serialises progress onto stderr as CLIXML, which an
/// exec hands back mixed into stdout.
bool _isPowerShellNoise(String line) =>
    line.startsWith('#< CLIXML') || line.startsWith('<Objs ');

/// Candidates out of [completeCommand]'s output. fish follows each with a tab
/// and a description, which is dropped.
List<String> parseCandidates(Uint8List output) {
  final seen = <String>{};
  return [
    for (final line in const LineSplitter().convert(
      utf8.decode(output, allowMalformed: true),
    ))
      if (line.split('\t').first.trimRight() case final c
          when c.isNotEmpty && !_isPowerShellNoise(c) && seen.add(c))
        c,
  ];
}
