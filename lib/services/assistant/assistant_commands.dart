import 'dart:math' as math;

/// Why a command the assistant wanted to run on its own was refused, or
/// null when it may run.
///
/// The assistant's `inspect` tool runs without asking the user, so this is
/// the one thing standing between a model - or whatever a server printed
/// into its context - and the user's server. It is deliberately narrow:
/// the command is cut at `|`, `&&`, `||` and `;`, and every piece has to
/// start with a program known to only read, used in a way that only reads.
/// Anything it does not recognise is refused; the assistant can still
/// propose it, and then the user decides.
String? refuseInspect(String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty) return 'empty command';
  if (trimmed.length > 2000) return 'command too long';
  if (trimmed.contains('\n') || trimmed.contains('\r')) {
    return 'more than one line';
  }
  for (final banned in const ['`', r'$(', '<(', '>(', '&>', '<<']) {
    if (trimmed.contains(banned)) return 'uses $banned';
  }
  final unquoted = _withoutQuoted(trimmed);
  if (unquoted == null) return 'unbalanced quotes';
  final redirect = _refuseRedirects(unquoted);
  if (redirect != null) return redirect;
  final bare = unquoted.replaceAll(_harmlessRedirect, ' ');
  if (RegExp(r'(^|[^&])&($|[^&])').hasMatch(bare)) {
    return 'runs something in the background';
  }
  var loops = 0;
  for (var piece in _pieces(trimmed)) {
    var words = _words(piece);
    if (words.isEmpty) return 'empty piece';
    if (words.first == 'for') {
      final head = _refuseLoopHead(words);
      if (head != null) return head;
      loops++;
      continue;
    }
    if (words.first == 'done') {
      if (loops == 0 || words.length > 1) return 'a loop that does not close';
      loops--;
      continue;
    }
    if (words.first == 'do') {
      if (loops == 0) return 'a loop that does not close';
      piece = piece.substring(2).trim();
      words = words.skip(1).toList();
      if (words.isEmpty) return 'empty piece';
    }
    final reason =
        (loops > 0 ? _refuseLoopBody(words) : null) ??
        _refuseProgram(words) ??
        _refuseFollow(words) ??
        _refuseSecrets(piece, words);
    if (reason != null) return reason;
  }
  if (loops != 0) return 'a loop that does not close';
  return null;
}

/// Why [command] is not even worth asking the user about - it is empty,
/// unreadably long, spans lines or never ends - or null. Anything else
/// [refuseInspect] turns down can still run once the user allows it.
String? refuseAsking(String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty) return 'empty command';
  if (trimmed.length > 2000) return 'command too long';
  if (trimmed.contains('\n') || trimmed.contains('\r')) {
    return 'more than one line';
  }
  for (final piece in _pieces(trimmed)) {
    final words = _words(piece);
    if (words.isEmpty) continue;
    final endless = _refuseFollow(
      words.first == 'do' ? words.skip(1).toList() : words,
    );
    if (endless != null) return endless;
  }
  return null;
}

/// `for NAME in WORDS`: a plain name, and nothing in the list that may hold
/// a secret.
String? _refuseLoopHead(List<String> words) {
  if (words.length < 3 ||
      !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(words[1]) ||
      words[2] != 'in') {
    return 'a loop that is not for NAME in ...';
  }
  for (final word in words.skip(3)) {
    final looksLikePath =
        word.contains('/') || word.startsWith('.') || word.startsWith('~');
    if (looksLikePath && mayHoldSecrets(word)) {
      return '$word may hold secrets; read it with read_file';
    }
  }
  return null;
}

/// Inside a loop a variable can name any file, which no check here can
/// see, so programs that print what files hold may not be handed one.
String? _refuseLoopBody(List<String> words) {
  final program = words.first.split('/').last;
  if (_contentReaders.contains(program) &&
      words.skip(1).any((w) => w.contains(r'$'))) {
    return '$program reads files a loop variable names';
  }
  return null;
}

/// Commands that never end on their own.
String? _refuseFollow(List<String> words) {
  final program = words.first.split('/').last;
  final args = words.skip(1);
  switch (program) {
    case 'tail':
    case 'journalctl':
      if (args.any(
        (a) =>
            a == '--follow' ||
            (a.startsWith('-') &&
                !a.startsWith('--') &&
                (a.contains('f') || a.contains('F'))),
      )) {
        return '$program follows forever';
      }
    case 'dmesg':
      if (args.any((a) => a == '-w' || a == '--follow' || a == '-W')) {
        return 'dmesg follows forever';
      }
    case 'ping':
      if (!args.any((a) => a == '-c' || a.startsWith('-c'))) {
        return 'ping needs -c';
      }
    case 'top':
      if (!args.any((a) => a == '-n' || a.startsWith('-n'))) {
        return 'top needs -n';
      }
    case 'vmstat':
    case 'iostat':
    case 'mpstat':
    case 'sar':
      if (args.where((a) => int.tryParse(a) != null).length == 1) {
        return '$program needs a count';
      }
  }
  return null;
}

/// Programs that print what is in the files they are given.
const _contentReaders = {
  'cat',
  'head',
  'tail',
  'grep',
  'egrep',
  'fgrep',
  'zgrep',
  'zcat',
  'less',
  'more',
  'strings',
  'od',
  'xxd',
  'hexdump',
  'awk',
  'sed',
  'tac',
  'nl',
  'rev',
  'jq',
  'diff',
  'cmp',
  'comm',
  'sort',
  'uniq',
  'cut',
  'column',
  'openssl',
};

/// Reading a file that may hold a secret goes through `read_file`, which
/// asks the user first; a wildcard could reach one without naming it.
String? _refuseSecrets(String piece, List<String> words) {
  for (final word in words.skip(1)) {
    final looksLikePath =
        word.contains('/') || word.startsWith('.') || word.startsWith('~');
    if (looksLikePath && mayHoldSecrets(word)) {
      return '$word may hold secrets; read it with read_file';
    }
  }
  final program = words.first.split('/').last;
  if (_contentReaders.contains(program)) {
    final unquoted = _withoutQuoted(piece) ?? piece;
    if (RegExp(r'[*?\[]').hasMatch(unquoted)) {
      return 'wildcards in files read by $program';
    }
  }
  return null;
}

/// Whether reading [path] may hand the assistant a secret, so the user is
/// asked first.
bool mayHoldSecrets(String path) {
  final lower = path.toLowerCase();
  final name = lower.split('/').last;
  if (lower.contains('/.ssh/') ||
      lower.endsWith('/.ssh') ||
      lower.startsWith('~/.ssh')) {
    return true;
  }
  if (lower == '/etc/shadow' || lower == '/etc/gshadow') return true;
  if (RegExp(r'^/proc/[^/]+/environ$').hasMatch(lower)) return true;
  if (name.startsWith('.env') || name.endsWith('.env')) return true;
  for (final ending in const ['.key', '.pem', '.p12', '.pfx', '.jks']) {
    if (name.endsWith(ending)) return true;
  }
  if (name.startsWith('id_')) return true;
  for (final word in const [
    'secret',
    'token',
    'password',
    'passwd',
    'credential',
    'private',
    '.netrc',
    '.pgpass',
    'htpasswd',
  ]) {
    if (name.contains(word)) return true;
  }
  return false;
}

/// [command] with every quoted stretch replaced by a placeholder, so `>`
/// or `&` inside an argument such as a grep pattern is not taken for an
/// operator. Null when a quote is left open.
String? _withoutQuoted(String command) {
  final out = StringBuffer();
  String? quote;
  for (var i = 0; i < command.length; i++) {
    final c = command[i];
    if (quote != null) {
      if (c == quote) {
        quote = null;
        out.write('Q');
      } else if (c == r'\' && quote == '"' && i + 1 < command.length) {
        i++;
      }
      continue;
    }
    if (c == r'\' && i + 1 < command.length) {
      i++;
      out.write('E');
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      continue;
    }
    out.write(c);
  }
  return quote == null ? out.toString() : null;
}

/// Throwing output away, or folding error output into the normal one.
final _harmlessRedirect = RegExp(r'\d?>\s*/dev/null|\d?>&\d');

/// Refuses any redirection except [_harmlessRedirect].
String? _refuseRedirects(String unquoted) {
  final rest = unquoted.replaceAll(_harmlessRedirect, ' ');
  if (rest.contains('>')) return 'writes to a file';
  if (rest.contains('<')) return 'reads input from a file';
  return null;
}

/// The command cut at `|`, `||`, `&&` and `;` outside quotes.
List<String> _pieces(String command) {
  final pieces = <String>[];
  final current = StringBuffer();
  String? quote;
  for (var i = 0; i < command.length; i++) {
    final c = command[i];
    if (quote != null) {
      current.write(c);
      if (c == quote) quote = null;
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      current.write(c);
      continue;
    }
    if (c == '|' ||
        c == ';' ||
        (c == '&' && i + 1 < command.length && command[i + 1] == '&')) {
      pieces.add(current.toString());
      current.clear();
      if (i + 1 < command.length &&
          (command[i + 1] == '|' || command[i + 1] == '&')) {
        i++;
      }
      continue;
    }
    current.write(c);
  }
  pieces.add(current.toString());
  return [
    for (final piece in pieces)
      if (piece.trim().isNotEmpty) piece.trim(),
  ];
}

/// The piece's words with quotes taken off and redirections to /dev/null
/// dropped.
List<String> _words(String piece) {
  final words = <String>[];
  final current = StringBuffer();
  String? quote;
  var any = false;
  for (var i = 0; i < piece.length; i++) {
    final c = piece[i];
    if (quote != null) {
      if (c == quote) {
        quote = null;
      } else {
        current.write(c);
      }
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      any = true;
      continue;
    }
    if (c == ' ' || c == '\t') {
      if (any || current.isNotEmpty) words.add(current.toString());
      current.clear();
      any = false;
      continue;
    }
    current.write(c);
  }
  if (any || current.isNotEmpty) words.add(current.toString());
  return [
    for (final word in words)
      if (!RegExp(r'^\d?>(&\d|/dev/null)?$').hasMatch(word) &&
          word != '/dev/null')
        word,
  ];
}

/// Programs that only ever read, whatever their arguments.
const _readers = {
  'ls',
  'cat',
  'head',
  'tail',
  'grep',
  'egrep',
  'fgrep',
  'zgrep',
  'zcat',
  'wc',
  'df',
  'du',
  'free',
  'uptime',
  'ps',
  'pgrep',
  'ss',
  'netstat',
  'uname',
  'hostname',
  'whoami',
  'id',
  'groups',
  'date',
  'lsblk',
  'findmnt',
  'stat',
  'file',
  'which',
  'whereis',
  'type',
  'dig',
  'nslookup',
  'host',
  'getent',
  'last',
  'lastlog',
  'w',
  'who',
  'lsof',
  'sort',
  'uniq',
  'cut',
  'tr',
  'echo',
  'printf',
  'true',
  'false',
  'test',
  'basename',
  'dirname',
  'readlink',
  'realpath',
  'nproc',
  'lscpu',
  'lsmod',
  'vmstat',
  'iostat',
  'mpstat',
  'sar',
  'dmesg',
  'column',
  'nl',
  'rev',
  'tac',
  'less',
  'more',
  'jq',
  'md5sum',
  'sha256sum',
  'sha1sum',
  'pwd',
  'tree',
  'arch',
  'locale',
  'timedatectl',
  'hostnamectl',
  'loginctl',
  'resolvectl',
  'networkctl',
  'ulimit',
  'diff',
  'cmp',
  'comm',
  'strings',
  'od',
  'xxd',
  'hexdump',
  'mount',
  'swapon',
  'ip',
  'ifconfig',
  'route',
  'arp',
  'traceroute',
  'tracepath',
  'mtr',
  'ping',
  'awk',
  'sed',
  'find',
  'top',
  'htop',
};

String? _refuseProgram(List<String> words) {
  var program = words.first;
  final args = words.skip(1).toList();
  if (program.contains('/')) program = program.split('/').last;
  if (program == 'sudo' || program == 'su' || program == 'doas') {
    return 'uses $program';
  }
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(program)) {
    return 'sets a variable';
  }
  switch (program) {
    case 'sed':
      if (args.any(
        (a) => a == '-i' || a.startsWith('-i') || a.startsWith('--in-place'),
      )) {
        return 'sed -i edits files';
      }
      if (args.any(
        (a) => a == '-f' || a.startsWith('--file') || a.startsWith('-f'),
      )) {
        return 'sed reads its script from a file';
      }
      if (_sedScripts(args).any(_sedWritesOrRuns)) {
        return 'sed script writes or runs';
      }
      return null;
    case 'awk':
      if (args.any(
        (a) =>
            RegExp(r'\bsystem\s*\(').hasMatch(a) ||
            RegExp(r'\bprintf?\b[^;}]*[>|]').hasMatch(a) ||
            RegExp(r'\|\s*getline').hasMatch(a) ||
            a.contains('|&'),
      )) {
        return 'awk program writes or runs';
      }
      return null;
    case 'find':
      for (final banned in const [
        '-delete',
        '-exec',
        '-execdir',
        '-ok',
        '-okdir',
        '-fprint',
        '-fprint0',
        '-fprintf',
        '-fls',
      ]) {
        if (args.contains(banned)) return 'find $banned';
      }
      return null;
    case 'top':
      return args.contains('-b') ? null : 'top needs -b';
    case 'htop':
      return 'htop is interactive';
    case 'less':
    case 'more':
      return 'interactive pager';
    case 'mount':
    case 'swapon':
      return args.every(
            (a) =>
                a.startsWith('-') &&
                !const ['-a', '--all', '-o', '-t', '-B', '--bind'].contains(a),
          )
          ? null
          : '$program with arguments changes the system';
    case 'ip':
      return _onlySubcommands(
            args,
            const {
              'a',
              'addr',
              'address',
              'r',
              'route',
              'l',
              'link',
              'n',
              'neigh',
              'neighbour',
              'rule',
              '-br',
              '-4',
              '-6',
              '-s',
              '-c',
              '-j',
              '-p',
            },
            const {
              'add',
              'del',
              'delete',
              'set',
              'change',
              'replace',
              'flush',
              'append',
            },
          )
          ? null
          : 'ip changes the network';
    case 'ifconfig':
    case 'route':
    case 'arp':
      return args.every((a) => a.startsWith('-'))
          ? null
          : '$program with arguments changes the network';
    case 'date':
      return args.any((a) => a == '-s' || a.startsWith('--set'))
          ? 'date sets the clock'
          : null;
    case 'hostname':
      return args.every((a) => a.startsWith('-'))
          ? null
          : 'hostname sets the name';
    case 'dmesg':
      return args.any(
            (a) =>
                a == '-c' || a == '-C' || a.startsWith('--clear') || a == '-n',
          )
          ? 'dmesg changes the log'
          : null;
    case 'timedatectl':
    case 'hostnamectl':
    case 'resolvectl':
    case 'networkctl':
    case 'loginctl':
      return args.isEmpty ||
              const {
                'status',
                'show',
                'list',
                'list-sessions',
                'list-users',
                'show-session',
                'show-user',
                'query',
                'statistics',
                'dns',
                'domain',
              }.contains(args.first)
          ? null
          : '$program ${args.first} changes the system';
    case 'ulimit':
      return args.every(
            (a) =>
                a.startsWith('-') && a.length == 2 && a != '-S' && a != '-H' ||
                a == '-a',
          )
          ? null
          : 'ulimit sets a limit';
    case 'systemctl':
      return _systemctl(args);
    case 'journalctl':
      for (final banned in const [
        '--vacuum-size',
        '--vacuum-time',
        '--vacuum-files',
        '--rotate',
        '--flush',
        '--sync',
        '--relinquish-var',
        '--setup-keys',
        '--update-catalog',
      ]) {
        if (args.any((a) => a.startsWith(banned))) return 'journalctl $banned';
      }
      return null;
    case 'docker':
    case 'podman':
      return _container(program, args);
    case 'kubectl':
      if (args.any((a) => RegExp(r'^secrets?($|/)').hasMatch(a)) &&
          args.any(
            (a) => a == '-o' || a.startsWith('-o') || a.startsWith('--output'),
          )) {
        return 'kubectl would print secret values';
      }
      return args.isNotEmpty &&
              const {
                'get',
                'describe',
                'logs',
                'top',
                'version',
                'cluster-info',
                'explain',
                'api-resources',
              }.contains(args.first)
          ? null
          : 'kubectl ${args.firstOrNull ?? ''} changes the cluster';
    case 'git':
      return 'git can run programs named in the repository\'s own settings';
    case 'nginx':
      return args.length == 1 &&
              (args.first == '-t' ||
                  args.first == '-T' ||
                  args.first == '-v' ||
                  args.first == '-V')
          ? null
          : 'nginx only with -t, -T, -v or -V';
    case 'apachectl':
    case 'apache2ctl':
      return args.length == 1 &&
              const {
                '-t',
                '-S',
                '-M',
                '-v',
                '-V',
                'configtest',
              }.contains(args.first)
          ? null
          : '$program only for checks';
    case 'curl':
      return _curl(args);
    case 'dpkg':
      return args.isNotEmpty &&
              const {
                '-l',
                '-L',
                '-s',
                '-S',
                '--list',
                '--listfiles',
                '--status',
                '--search',
                '--print-architecture',
              }.contains(args.first)
          ? null
          : 'dpkg changes packages';
    case 'apt':
      return args.isNotEmpty &&
              const {'list', 'show', 'policy', 'search'}.contains(args.first)
          ? null
          : 'apt changes packages';
    case 'apt-cache':
      return null;
    case 'rpm':
      return args.isNotEmpty && args.first.startsWith('-q')
          ? null
          : 'rpm changes packages';
    case 'crontab':
      return args.length == 1 && args.first == '-l'
          ? null
          : 'crontab only with -l';
    case 'openssl':
      return args.isNotEmpty &&
              const {
                'x509',
                's_client',
                'version',
                'verify',
                'req',
                'ciphers',
              }.contains(args.first) &&
              !args.contains('-out')
          ? null
          : 'openssl writes files';
    case 'node':
    case 'python':
    case 'python3':
    case 'php':
    case 'java':
    case 'go':
    case 'ruby':
    case 'npm':
    case 'pnpm':
    case 'yarn':
      return args.length == 1 &&
              const {'-v', '--version', '-V', 'version'}.contains(args.first)
          ? null
          : '$program runs code';
  }
  if (_readers.contains(program)) return null;
  return '$program is not on the read-only list';
}

bool _onlySubcommands(
  List<String> args,
  Set<String> allowed,
  Set<String> banned,
) {
  if (args.any(banned.contains)) return false;
  return args.isEmpty ||
      allowed.contains(args.first) ||
      args.first.startsWith('-');
}

String? _systemctl(List<String> args) {
  final verbs = args.where((a) => !a.startsWith('-')).toList();
  const reading = {
    'status',
    'show',
    'cat',
    'is-active',
    'is-enabled',
    'is-failed',
    'list-units',
    'list-unit-files',
    'list-timers',
    'list-sockets',
    'list-dependencies',
    'list-jobs',
    'get-default',
    'is-system-running',
    'show-environment',
  };
  if (verbs.isEmpty) return null;
  return reading.contains(verbs.first)
      ? null
      : 'systemctl ${verbs.first} changes the system';
}

String? _container(String program, List<String> args) {
  final verbs = args.where((a) => !a.startsWith('-')).toList();
  if (verbs.isEmpty) return null;
  const reading = {
    'ps',
    'logs',
    'inspect',
    'images',
    'stats',
    'top',
    'version',
    'info',
    'port',
    'diff',
    'history',
    'events',
    'df',
  };
  if (verbs.first == 'compose' ||
      verbs.first == 'container' ||
      verbs.first == 'image' ||
      verbs.first == 'network' ||
      verbs.first == 'volume' ||
      verbs.first == 'system') {
    final next = verbs.length > 1 ? verbs[1] : '';
    return const {
          'ps',
          'logs',
          'ls',
          'inspect',
          'config',
          'top',
          'images',
          'df',
          'info',
          'version',
        }.contains(next)
        ? null
        : '$program ${verbs.first} $next changes containers';
  }
  if (verbs.first == 'stats' && !args.contains('--no-stream')) {
    return '$program stats needs --no-stream';
  }
  if (verbs.first == 'logs' &&
      (args.contains('-f') || args.contains('--follow'))) {
    return '$program logs -f never ends';
  }
  if (verbs.first == 'events' && !args.any((a) => a.startsWith('--until'))) {
    return '$program events needs --until';
  }
  return reading.contains(verbs.first)
      ? null
      : '$program ${verbs.first} changes containers';
}

String? _curl(List<String> args) {
  for (final arg in args) {
    if (const {
          '-X',
          '--request',
          '-d',
          '--data',
          '--data-raw',
          '--data-binary',
          '--data-urlencode',
          '-F',
          '--form',
          '-T',
          '--upload-file',
          '-o',
          '--output',
          '-O',
          '--remote-name',
          '-K',
          '--config',
          '-c',
          '--cookie-jar',
          '--json',
        }.contains(arg) ||
        arg.startsWith('--data') ||
        arg.startsWith('--output') ||
        (arg.startsWith('-') &&
            !arg.startsWith('--') &&
            RegExp('[XdFTOoKc]').hasMatch(arg.substring(1)))) {
      return 'curl only fetches';
    }
  }
  return null;
}

/// The scripts a sed command runs: each `-e` or `--expression`, or else its
/// first argument that is not an option.
List<String> _sedScripts(List<String> args) {
  final scripts = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-e' || arg == '--expression') {
      if (i + 1 < args.length) scripts.add(args[++i]);
    } else if (arg.startsWith('--expression=')) {
      scripts.add(arg.substring('--expression='.length));
    } else if (arg.startsWith('-e') && arg.length > 2) {
      scripts.add(arg.substring(2));
    }
  }
  if (scripts.isNotEmpty) return scripts;
  final first = args.where((a) => !a.startsWith('-')).firstOrNull;
  return first == null ? const [] : [first];
}

/// Whether a sed [script] has a command that runs a program or writes a
/// file: `e`, `w` or `W`, or an `s` command with the `e` or `w` flag.
bool _sedWritesOrRuns(String script) {
  final address = RegExp(
    r'^\s*(?:(?:\d+|\$|/(?:[^/\\]|\\.)*/[IM]*)(?:~\d+)?'
    r'(?:\s*,\s*(?:\d+|\$|/(?:[^/\\]|\\.)*/[IM]*|[+~]\d+))?)?\s*!?\s*',
  );
  for (var command in script.split(RegExp(r'[;\n]'))) {
    command = command.trim();
    while (true) {
      command = command.replaceFirst(address, '');
      if (command.startsWith('{')) {
        command = command.substring(1);
        continue;
      }
      break;
    }
    command = command.replaceAll(RegExp(r'}+\s*$'), '').trim();
    if (command.isEmpty) continue;
    final name = command[0];
    if (name == 'e' || name == 'w' || name == 'W') return true;
    if (name == 's' && command.length > 1) {
      final delimiter = command[1];
      var seen = 0;
      var i = 2;
      for (; i < command.length && seen < 2; i++) {
        if (command[i] == '\\') {
          i++;
        } else if (command[i] == delimiter) {
          seen++;
        }
      }
      final flags = command.substring(math.min(i, command.length));
      if (flags.contains('e') || flags.contains('w')) return true;
    }
  }
  return false;
}
