class SshLink {
  const SshLink({required this.host, this.port = 22, this.user});

  final String host;
  final int port;
  final String? user;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshLink &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          user == other.user;

  @override
  int get hashCode => Object.hash(host, port, user);

  @override
  String toString() => 'SshLink(host: $host, port: $port, user: $user)';
}

/// Parses an `ssh://[user@]host[:port]` URI into an [SshLink].
///
/// Returns null for invalid schemes, missing or empty hosts, invalid ports, or
/// URIs containing paths beyond a bare slash, queries, or fragments.
///
/// A password in the userinfo is dropped, so a received credential is never
/// stored.
SshLink? parseSshLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;

  if (uri.scheme.toLowerCase() != 'ssh') return null;

  if (!uri.hasAuthority) return null;

  if (uri.path.isNotEmpty && uri.path != '/') return null;
  if (uri.hasQuery || uri.hasFragment) return null;

  var host = uri.host;
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  if (host.isEmpty) return null;

  final portText = _rawPortText(raw.trim());
  final int port;
  if (portText == null) {
    port = 22;
  } else {
    final parsed = int.tryParse(portText);
    if (parsed == null || parsed < 1 || parsed > 65535) return null;
    port = parsed;
  }

  String? user;
  if (uri.userInfo.isNotEmpty) {
    final userPart = uri.userInfo.split(':').first;
    if (userPart.isNotEmpty) {
      user = userPart;
    }
  }

  return SshLink(host: host, port: port, user: user);
}

/// The port exactly as the link spelled it, or null when it named none.
///
/// [Uri] cannot answer this. It treats `:0` as no port at all and erases it
/// from `authority`, so by the time a link has been parsed one naming port 0
/// is indistinguishable from one naming none - and defaulting that to 22 is
/// how a malformed link quietly reaches a different service than it said.
///
/// An IPv6 literal carries colons of its own, so only what follows its
/// closing bracket can be a port.
String? _rawPortText(String raw) {
  final schemeEnd = raw.indexOf('://');
  if (schemeEnd < 0) return null;
  var authority = raw.substring(schemeEnd + 3);

  final end = authority.indexOf(RegExp(r'[/?#]'));
  if (end >= 0) authority = authority.substring(0, end);

  final at = authority.lastIndexOf('@');
  if (at >= 0) authority = authority.substring(at + 1);

  final bracket = authority.lastIndexOf(']');
  final colon = authority.indexOf(':', bracket + 1);
  if (colon < 0) return null;
  return authority.substring(colon + 1);
}

/// ssh's options that take an argument, so the argument is not read as the
/// host - `ssh -i ~/.ssh/key ops@db`.
const _optionsWithArgument = {
  'B', 'b', 'c', 'D', 'E', 'e', 'F', 'I', 'i', 'J', 'L', 'l', 'm', 'O', 'o', //
  'p', 'Q', 'R', 'S', 'W', 'w',
};

/// Reads what someone types to add a machine: `user@host`, `host:port`, an
/// `ssh ...` command pasted from a terminal, or an `ssh://` link.
///
/// Only the target is taken from a command. Everything else ssh would do with
/// its flags - keys, jump hosts, forwards - is set in the form, so the flags
/// are stepped over, and anything after the host is refused rather than
/// guessed at: `ssh host uptime` is not a machine.
///
/// One colon in the target is `host:port`; more than one is a bare IPv6
/// address.
SshLink? parseSshTarget(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text.toLowerCase().startsWith('ssh://')) return parseSshLink(text);

  final words = text.split(RegExp(r'\s+'));
  var i = 0;
  if (words.first == 'ssh') {
    i = 1;
  } else if (words.length > 1) {
    return null;
  }

  String? user;
  int? port;
  String? target;
  for (; i < words.length; i++) {
    final word = words[i];
    if (word.length > 1 && word.startsWith('-')) {
      final flag = word[1];
      if (!_optionsWithArgument.contains(flag)) continue;
      final value = word.length > 2
          ? word.substring(2)
          : (i + 1 < words.length ? words[++i] : null);
      if (value == null) return null;
      if (flag == 'p') {
        port = _port(value);
        if (port == null) return null;
      } else if (flag == 'l') {
        user = value;
      }
      continue;
    }
    if (target != null) return null;
    target = word;
  }
  if (target == null) return null;

  var hostPart = target;
  final at = target.lastIndexOf('@');
  if (at >= 0) {
    final named = target.substring(0, at);
    if (named.isEmpty) return null;
    user = named;
    hostPart = target.substring(at + 1);
  }

  String host;
  if (hostPart.startsWith('[')) {
    final close = hostPart.indexOf(']');
    if (close < 0) return null;
    host = hostPart.substring(1, close);
    final rest = hostPart.substring(close + 1);
    if (rest.isNotEmpty) {
      if (!rest.startsWith(':')) return null;
      port = _port(rest.substring(1));
      if (port == null) return null;
    }
  } else if (':'.allMatches(hostPart).length == 1) {
    final colon = hostPart.indexOf(':');
    host = hostPart.substring(0, colon);
    port = _port(hostPart.substring(colon + 1));
    if (port == null) return null;
  } else {
    host = hostPart;
  }
  if (host.isEmpty || host.contains(RegExp(r'[/@\s]'))) return null;

  return SshLink(host: host, port: port ?? 22, user: user);
}

int? _port(String text) {
  if (!RegExp(r'^\d{1,5}$').hasMatch(text)) return null;
  final port = int.parse(text);
  return port >= 1 && port <= 65535 ? port : null;
}
