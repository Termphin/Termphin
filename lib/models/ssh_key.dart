import 'dart:convert';

import '../services/storage/group_storage.dart';

enum SshKeyType {
  ed25519,
  rsa2048,
  rsa4096;

  String get label => switch (this) {
    SshKeyType.ed25519 => 'ed25519',
    SshKeyType.rsa2048 => 'rsa 2048',
    SshKeyType.rsa4096 => 'rsa 4096',
  };
}

class SshKey {
  SshKey({
    required this.id,
    required this.name,
    required this.keyType,
    required this.privateKeyPem,
    required this.publicKeyOpenSSH,
    required this.createdAt,
    DateTime? updatedAt,
    this.group = GroupStorage.defaultGroup,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String name;
  final SshKeyType keyType;
  final String privateKeyPem;
  final String publicKeyOpenSSH;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String group;

  SshKey copyWith({
    String? id,
    String? name,
    SshKeyType? keyType,
    String? privateKeyPem,
    String? publicKeyOpenSSH,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? group,
  }) {
    return SshKey(
      id: id ?? this.id,
      name: name ?? this.name,
      keyType: keyType ?? this.keyType,
      privateKeyPem: privateKeyPem ?? this.privateKeyPem,
      publicKeyOpenSSH: publicKeyOpenSSH ?? this.publicKeyOpenSSH,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      group: group ?? this.group,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'keyType': keyType.name,
      'privateKeyPem': privateKeyPem,
      'publicKeyOpenSSH': publicKeyOpenSSH,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'group': group,
    };
  }

  factory SshKey.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    return SshKey(
      id: json['id'] as String,
      name: json['name'] as String,
      keyType: SshKeyType.values.firstWhere(
        (t) => t.name == json['keyType'],
        orElse: () => SshKeyType.ed25519,
      ),
      privateKeyPem: json['privateKeyPem'] as String,
      publicKeyOpenSSH: json['publicKeyOpenSSH'] as String,
      createdAt: createdAt,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : createdAt,
      group:
          json['group'] as String? ??
          (json['tags'] is List && (json['tags'] as List).isNotEmpty
              ? (json['tags'] as List).first.toString()
              : GroupStorage.defaultGroup),
    );
  }

  String get formattedDate {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[createdAt.month - 1]} ${createdAt.day}, ${createdAt.year}';
  }

  String encode() => jsonEncode(toJson());

  static SshKey decode(String raw) {
    return SshKey.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
