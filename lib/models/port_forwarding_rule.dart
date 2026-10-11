enum ForwardType { local, remote }

enum TunnelStatus { idle, starting, active, error }

class PortForwardingRule {
  const PortForwardingRule({
    required this.id,
    required this.type,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    this.localHost = 'localhost',
    this.name,
    required this.createdAt,
  });

  final String id;
  final String? name;
  final ForwardType type;
  final int localPort;
  final String remoteHost;
  final int remotePort;
  final String localHost;
  final DateTime createdAt;

  String get displayName => name ?? _defaultLabel;

  String get _defaultLabel {
    final prefix = type == ForwardType.local ? 'L' : 'R';
    return '$prefix:$localPort→$remoteHost:$remotePort';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'localPort': localPort,
      'remoteHost': remoteHost,
      'remotePort': remotePort,
      'localHost': localHost,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PortForwardingRule.fromJson(Map<String, dynamic> json) {
    return PortForwardingRule(
      id: json['id'] as String,
      name: json['name'] as String?,
      type: ForwardType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ForwardType.local,
      ),
      localPort: (json['localPort'] as num).toInt(),
      remoteHost: json['remoteHost'] as String,
      remotePort: (json['remotePort'] as num).toInt(),
      localHost: (json['localHost'] as String?) ?? 'localhost',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  PortForwardingRule copyWith({
    String? id,
    String? name,
    ForwardType? type,
    int? localPort,
    String? remoteHost,
    int? remotePort,
    String? localHost,
    DateTime? createdAt,
    bool clearName = false,
  }) {
    return PortForwardingRule(
      id: id ?? this.id,
      name: clearName ? null : (name ?? this.name),
      type: type ?? this.type,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      localHost: localHost ?? this.localHost,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
