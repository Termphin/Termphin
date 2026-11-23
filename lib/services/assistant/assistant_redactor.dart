/// Hides who and where the user is from the assistant, and puts it back in
/// what the assistant says.
///
/// Everything sent to the model passes through [hide]: anything that looks
/// like a secret becomes `[SECRET_n]`, and the server's names, addresses,
/// users and emails become `HOST_n`, `IP_n`, `USER_n` and `EMAIL_n`. What
/// the model sends back passes through [reveal] before the app shows or runs
/// it. A value keeps its placeholder for the whole conversation, so the
/// model can follow it, and the same text always hides the same way, so the
/// conversation sent again next step is the one sent before.
///
/// Loopback and unspecified addresses stay as they are: `127.0.0.1:3000`
/// says where an app listens, not whose server it is.
class AssistantRedactor {
  AssistantRedactor({
    Iterable<String> hosts = const [],
    Iterable<String> users = const [],
  }) {
    for (final host in hosts) {
      _remember(_hosts, host.trim().toLowerCase(), 'HOST');
    }
    for (final user in users) {
      final name = user.trim();
      if (name.length >= 3 && !_commonUsers.contains(name.toLowerCase())) {
        _remember(_users, name, 'USER');
      }
    }
  }

  final _hosts = <String, String>{};
  final _users = <String, String>{};
  final _ips = <String, String>{};
  final _emails = <String, String>{};
  final _secrets = <String, String>{};
  final _originals = <String, String>{};

  static const _commonUsers = {
    'root',
    'admin',
    'user',
    'ubuntu',
    'debian',
    'www-data',
    'nginx',
    'nobody',
    'daemon',
    'systemd',
    'postgres',
    'mysql',
    'redis',
    'node',
  };

  /// [text] with everything identifying replaced by placeholders.
  String hide(String text) {
    var out = text;
    for (final pattern in _secretPatterns) {
      out = out.replaceAllMapped(pattern.regex, (m) {
        final secret = m.group(pattern.group)!;
        if (_placeholder.hasMatch(secret)) return m.group(0)!;
        final placeholder = _remember(
          _secrets,
          secret,
          'SECRET',
          bracketed: true,
        );
        return m.group(0)!.replaceFirst(secret, placeholder);
      });
    }
    out = out.replaceAllMapped(
      _email,
      (m) => _remember(_emails, m.group(0)!.toLowerCase(), 'EMAIL'),
    );
    out = out.replaceAllMapped(_ipv4, (m) {
      final ip = m.group(0)!;
      if (_keptAddresses.contains(ip)) return ip;
      return _remember(_ips, ip, 'IP');
    });
    out = out.replaceAllMapped(_ipv6Candidate, (m) {
      final candidate = m.group(0)!;
      if (_keptAddresses.contains(candidate) || !_isIPv6(candidate)) {
        return candidate;
      }
      return _remember(_ips, candidate.toLowerCase(), 'IP');
    });
    out = out.replaceAllMapped(_homeDirectory, (m) {
      final name = m.group(1)!;
      if (_commonUsers.contains(name.toLowerCase())) return m.group(0)!;
      return '${m.group(0)!.substring(0, m.group(0)!.length - name.length)}${_remember(_users, name, 'USER')}';
    });
    for (final entry in _longestFirst(_hosts)) {
      out = out.replaceAll(
        RegExp(
          r'(?<![\w.-])' + RegExp.escape(entry.key) + r'(?![\w-]|\.\w)',
          caseSensitive: false,
        ),
        entry.value,
      );
    }
    for (final entry in _longestFirst(_users)) {
      out = out.replaceAll(
        RegExp(r'(?<![\w.-])' + RegExp.escape(entry.key) + r'(?![\w-])'),
        entry.value,
      );
    }
    return out;
  }

  /// [text] with every placeholder this redactor made put back.
  String reveal(String text) => text.replaceAllMapped(
    _placeholder,
    (m) => _originals[m.group(0)!] ?? m.group(0)!,
  );

  /// Every placeholder and what it stands for, for keeping a conversation.
  Map<String, String> get placeholders => Map.unmodifiable(_originals);

  String _remember(
    Map<String, String> map,
    String value,
    String kind, {
    bool bracketed = false,
  }) {
    final known = map[value];
    if (known != null) return known;
    final index = map.length + 1;
    final placeholder = bracketed ? '[${kind}_$index]' : '${kind}_$index';
    map[value] = placeholder;
    _originals[placeholder] = value;
    return placeholder;
  }

  static List<MapEntry<String, String>> _longestFirst(
    Map<String, String> map,
  ) =>
      map.entries.where((e) => e.key.isNotEmpty).toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));

  static final _placeholder = RegExp(
    r'\[SECRET_\d+\]|\b(?:HOST|IP|USER|EMAIL)_\d+\b',
  );

  static const _keptAddresses = {
    '127.0.0.1',
    '0.0.0.0',
    '::1',
    '::',
    '255.255.255.255',
  };

  static final _email = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
  );

  static final _ipv4 = RegExp(
    r'(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\d.]*\d)',
  );

  /// Runs of hex digits and colons with at least two colons; [_isIPv6]
  /// tells an address from a time of day.
  static final _ipv6Candidate = RegExp(
    r'(?<![\w:.])[0-9A-Fa-f]*:[0-9A-Fa-f:]*:[0-9A-Fa-f]*(?![\w:])',
  );

  static bool _isIPv6(String candidate) {
    try {
      Uri.parseIPv6Address(candidate);
      return true;
    } on FormatException {
      return false;
    }
  }

  static final _homeDirectory = RegExp(r'(?:/home/|/Users/)([A-Za-z0-9._-]+)');

  static final _secretPatterns = <({RegExp regex, int group})>[
    (
      regex: RegExp(
        r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
      ),
      group: 0,
    ),
    (regex: RegExp(r'\b[a-z][a-z0-9+.-]*://[^\s:/@]+:([^\s@/]+)@'), group: 1),
    (
      regex: RegExp(
        r'\b[A-Za-z0-9_]*(?:PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|AUTH_?KEY|CREDENTIALS?)[A-Za-z0-9_]*\s*[=:]\s*"?([^\s"]{4,})',
        caseSensitive: false,
      ),
      group: 1,
    ),
    (regex: RegExp(r'\b[Bb]earer\s+([A-Za-z0-9._~+/=-]{16,})'), group: 1),
    (regex: RegExp(r'\bAKIA[0-9A-Z]{16}\b'), group: 0),
    (regex: RegExp(r'\bgh[pousr]_[A-Za-z0-9]{30,}\b'), group: 0),
    (regex: RegExp(r'\bgithub_pat_[A-Za-z0-9_]{30,}\b'), group: 0),
    (
      regex: RegExp(r'\b(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{16,}\b'),
      group: 0,
    ),
    (regex: RegExp(r'\bxox[abposr]-[A-Za-z0-9-]{10,}\b'), group: 0),
    (regex: RegExp(r'\bsk-[A-Za-z0-9_-]{20,}\b'), group: 0),
    (regex: RegExp(r'\bAIza[0-9A-Za-z_-]{35}\b'), group: 0),
    (
      regex: RegExp(
        r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
      ),
      group: 0,
    ),
  ];
}
