/// One host key this device has accepted, keyed the way OpenSSH keys
/// `known_hosts`: by address, port *and* key type.
///
/// The type belongs in the key because a server legitimately offers several
/// host keys (ed25519, rsa, ecdsa) and which one is negotiated depends on the
/// algorithm lists both ends propose. Pinning only by address would read a
/// perfectly normal switch from one of the server's own keys to another as a
/// key change, and cry wolf often enough that the warning stops meaning
/// anything.
class KnownHost {
  const KnownHost({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.addedAt,
  });

  final String host;
  final int port;

  /// The SSH host key algorithm, e.g. `ssh-ed25519`.
  final String keyType;

  /// OpenSSH-style `SHA256:<base64>`, exactly as dartssh2 reports it, so the
  /// string shown to the user is the string compared against and the one they
  /// can check with `ssh-keygen -lf` on the server.
  final String fingerprint;

  final DateTime addedAt;

  /// Identity within the store. Not persisted - derived on both sides so a
  /// stored record can never disagree with its own key.
  String get slot => '$host:$port/$keyType';

  static String slotFor(String host, int port, String keyType) =>
      '$host:$port/$keyType';

  KnownHost copyWith({String? fingerprint, DateTime? addedAt}) => KnownHost(
    host: host,
    port: port,
    keyType: keyType,
    fingerprint: fingerprint ?? this.fingerprint,
    addedAt: addedAt ?? this.addedAt,
  );

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'keyType': keyType,
    'fingerprint': fingerprint,
    'addedAt': addedAt.toIso8601String(),
  };

  factory KnownHost.fromJson(Map<String, dynamic> json) => KnownHost(
    host: json['host'] as String,
    port: json['port'] as int,
    keyType: json['keyType'] as String,
    fingerprint: json['fingerprint'] as String,
    addedAt: DateTime.parse(json['addedAt'] as String),
  );
}

/// What the store makes of a host key the server just presented.
enum HostKeyVerdict {
  /// Pinned, and the fingerprint matches. Connect without asking.
  trusted,

  /// Never seen this host with this key type. First contact - ask once and
  /// pin the answer (trust on first use).
  unknown,

  /// Pinned with a *different* fingerprint. Either the server was rebuilt or
  /// someone is between the two ends; only the user can tell which.
  changed,
}
