/// What the assistant is told about the server it works on: its system,
/// its shell and the editors a change can be made with, read once when a
/// conversation binds to a session. Linux and macOS take the same commands
/// but not the same `sed`; Windows takes PowerShell.
library;

/// The command that asks a POSIX server about itself. Every line is one
/// fact, each prefixed so that a missing one is simply absent.
const kUnixSystemProbe =
    'echo "uname=\$(uname -s) \$(uname -r)"; '
    '(. /etc/os-release 2>/dev/null && echo "distro=\$PRETTY_NAME"); '
    'sw_vers -productVersion 2>/dev/null | sed "s/^/macos=/"; '
    'echo "shell=\$SHELL"; '
    'command -v python3 >/dev/null 2>&1 && echo "has=python3"; '
    'command -v perl >/dev/null 2>&1 && echo "has=perl"; true';

/// The same for a Windows server, in PowerShell.
const kWindowsSystemProbe =
    r'"windows=" + (Get-CimInstance Win32_OperatingSystem).Caption; '
    r'"powershell=" + $PSVersionTable.PSVersion.ToString()';

/// One sentence describing the server from [output] of the probe, or null
/// when the output says nothing usable.
String? describeServerSystem(String output, {required bool windows}) {
  final facts = <String, List<String>>{};
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final at = line.indexOf('=');
    if (at <= 0) continue;
    final key = line.substring(0, at).trim();
    final value = line.substring(at + 1).trim();
    if (value.isEmpty) continue;
    (facts[key] ??= []).add(value);
  }
  String? one(String key) => facts[key]?.first;
  if (windows) {
    final system = one('windows');
    if (system == null) return null;
    final shell = one('powershell');
    return 'The server runs $system'
        '${shell == null ? '' : ', PowerShell $shell'}. '
        'Use PowerShell commands, not POSIX ones.';
  }
  final uname = one('uname');
  if (uname == null) return null;
  final kernel = uname.split(' ').first;
  final macos = one('macos');
  final distro = one('distro');
  final system = macos != null
      ? 'macOS $macos'
      : distro != null
      ? '$distro ($uname)'
      : uname;
  final shell = one('shell')?.split('/').last;
  final tools = facts['has'] ?? const <String>[];
  final bsd = macos != null || kernel == 'Darwin' || kernel.endsWith('BSD');
  return [
    'The server runs $system',
    if (shell != null) ', shell $shell',
    '. ',
    tools.isEmpty
        ? 'Neither python3 nor perl is installed.'
        : '${tools.join(' and ')} ${tools.length == 1 ? 'is' : 'are'} installed.',
    if (bsd) ' Its sed is BSD sed: edit in place with sed -i \'\'.',
  ].join();
}
