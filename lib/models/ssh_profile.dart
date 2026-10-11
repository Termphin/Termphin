import 'dart:convert';

import '../services/storage/group_storage.dart';
import 'port_forwarding_rule.dart';

enum AuthMethod { none, password, privateKey }

class SshProfile {
  SshProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authMethod,
    this.password,
    this.privateKey,
    this.passphrase,
    this.sshKeyId,
    required this.createdAt,
    DateTime? updatedAt,
    this.lastConnectedAt,
    this.portForwardings = const [],
    this.group = GroupStorage.defaultGroup,
    this.iconName,
    this.colorHex,
    this.fallbackHosts = const [],
    this.lastGoodHost,
    this.mainHostFirst = true,
    this.jumpHostProfileId,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final AuthMethod authMethod;
  final String? password;
  final String? privateKey;
  final String? passphrase;
  final String? sshKeyId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastConnectedAt;
  final List<PortForwardingRule> portForwardings;
  final String group;
  final String? iconName;
  final String? colorHex;

  /// Alternative addresses for the same machine, tried in order after [host]
  /// when it is unreachable - e.g. a LAN IP, a Tailscale IP, a public DNS
  /// name. Each entry is `host` or `host:port`; a missing port falls back to
  /// [port].
  final List<String> fallbackHosts;

  /// The entry from [connectionCandidates] that last completed a connection,
  /// so a fallback that worked is tried before the other fallbacks.
  final String? lastGoodHost;

  /// Whether [host] leads [connectionCandidates] even after a fallback has
  /// worked. Off brings back the order from before 1.11.0, [lastGoodHost]
  /// ahead of everything, for a machine that is mostly reached through a
  /// fallback and would otherwise wait out the main address's timeout on
  /// every connect.
  final bool mainHostFirst;

  /// Another profile to connect through, OpenSSH's `ProxyJump`.
  ///
  /// A profile rather than a bare address, because a bastion is a host like
  /// any other - it has its own credentials, its own key and its own host key
  /// to verify, and duplicating all of that inline would mean maintaining it
  /// twice. The hop is a real SSH session to the bastion carrying a forwarded
  /// channel, so the session with the target is still end-to-end encrypted
  /// and its host key is still checked: the bastion moves the bytes, it does
  /// not get to read them.
  final String? jumpHostProfileId;

  /// [host] followed by [fallbackHosts], with [lastGoodHost] (if still one of
  /// them) first among the fallbacks. This is the order [SshService.connect]
  /// tries candidates in. [host] leads unless [mainHostFirst] is off: a
  /// fallback that worked once (Tailscale away from home) usually keeps
  /// working, so leading with it would never give the main address another
  /// chance. A blank entry is a row the user started and abandoned, not an
  /// address, and is dropped rather than tried.
  List<String> get connectionCandidates {
    final fallbacks = fallbackHosts
        .where((entry) => entry.trim().isNotEmpty)
        .toList();
    final good = lastGoodHost;
    if (good == null || !fallbacks.remove(good)) return [host, ...fallbacks];
    return mainHostFirst
        ? [host, good, ...fallbacks]
        : [good, host, ...fallbacks];
  }

  SshProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    AuthMethod? authMethod,
    String? password,
    String? privateKey,
    String? passphrase,
    String? sshKeyId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastConnectedAt,
    List<PortForwardingRule>? portForwardings,
    String? group,
    String? iconName,
    String? colorHex,
    List<String>? fallbackHosts,
    String? lastGoodHost,
    bool? mainHostFirst,
    String? jumpHostProfileId,
    bool clearJumpHost = false,
    bool clearPassword = false,
    bool clearPassphrase = false,
    bool clearSshKeyId = false,
    bool clearPrivateKey = false,
    bool clearLastConnectedAt = false,
    bool clearIconName = false,
    bool clearColorHex = false,
    bool clearLastGoodHost = false,
  }) {
    return SshProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      password: clearPassword ? null : (password ?? this.password),
      privateKey: clearPrivateKey ? null : (privateKey ?? this.privateKey),
      passphrase: clearPassphrase ? null : (passphrase ?? this.passphrase),
      sshKeyId: clearSshKeyId ? null : (sshKeyId ?? this.sshKeyId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastConnectedAt: clearLastConnectedAt
          ? null
          : (lastConnectedAt ?? this.lastConnectedAt),
      portForwardings: portForwardings ?? this.portForwardings,
      group: group ?? this.group,
      iconName: clearIconName ? null : (iconName ?? this.iconName),
      colorHex: clearColorHex ? null : (colorHex ?? this.colorHex),
      fallbackHosts: fallbackHosts ?? this.fallbackHosts,
      lastGoodHost: clearLastGoodHost
          ? null
          : (lastGoodHost ?? this.lastGoodHost),
      mainHostFirst: mainHostFirst ?? this.mainHostFirst,
      jumpHostProfileId: clearJumpHost
          ? null
          : (jumpHostProfileId ?? this.jumpHostProfileId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'authMethod': authMethod.name,
      'password': password,
      'privateKey': privateKey,
      'passphrase': passphrase,
      'sshKeyId': sshKeyId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      'portForwardings': portForwardings.map((r) => r.toJson()).toList(),
      'group': group,
      'iconName': iconName,
      'colorHex': colorHex,
      'fallbackHosts': fallbackHosts,
      'lastGoodHost': lastGoodHost,
      'mainHostFirst': mainHostFirst,
      'jumpHostProfileId': jumpHostProfileId,
    };
  }

  factory SshProfile.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    final group =
        json['group'] as String? ??
        (json['tags'] as List<dynamic>?)?.cast<String>().firstOrNull ??
        GroupStorage.defaultGroup;

    return SshProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: (json['port'] as num).toInt(),
      username: json['username'] as String,
      authMethod: AuthMethod.values.firstWhere(
        (method) => method.name == json['authMethod'],
        orElse: () => AuthMethod.password,
      ),
      password: json['password'] as String?,
      privateKey: json['privateKey'] as String?,
      passphrase: json['passphrase'] as String?,
      sshKeyId: json['sshKeyId'] as String?,
      createdAt: createdAt,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : createdAt,
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.parse(json['lastConnectedAt'] as String)
          : null,
      portForwardings:
          (json['portForwardings'] as List<dynamic>?)
              ?.map(
                (e) => PortForwardingRule.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      group: group,
      iconName: json['iconName'] as String?,
      colorHex: json['colorHex'] as String?,
      fallbackHosts:
          (json['fallbackHosts'] as List<dynamic>?)?.cast<String>() ?? [],
      lastGoodHost: json['lastGoodHost'] as String?,
      mainHostFirst: json['mainHostFirst'] as bool? ?? true,
      jumpHostProfileId: json['jumpHostProfileId'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static SshProfile decode(String raw) {
    return SshProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static List<String> encodeList(List<SshProfile> profiles) {
    return profiles.map((profile) => profile.encode()).toList();
  }

  static List<SshProfile> decodeList(List<String> rawProfiles) {
    return rawProfiles.map(SshProfile.decode).toList();
  }
}

/// One address to attempt a connection against: a bare hostname/IP, or a
/// `host:port` pair overriding the profile's default port.
class SshEndpoint {
  const SshEndpoint(this.host, this.port);

  final String host;
  final int port;

  /// Parses a [SshProfile.connectionCandidates] entry. IPv6 literals (which
  /// contain their own colons) are only treated as carrying a port override
  /// when bracketed, e.g. `[::1]:2222`, so a bare `::1` is not misread. A
  /// bracketed address with no port, e.g. `[::1]`, is what a paste from a URL
  /// looks like - the brackets are URL syntax, not part of the address.
  factory SshEndpoint.parse(String entry, {required int defaultPort}) {
    final bracketed = RegExp(r'^\[(.+)\]:(\d+)$').firstMatch(entry);
    if (bracketed != null) {
      return SshEndpoint(bracketed.group(1)!, int.parse(bracketed.group(2)!));
    }
    final bareBracketed = RegExp(r'^\[(.+)\]$').firstMatch(entry);
    if (bareBracketed != null) {
      return SshEndpoint(bareBracketed.group(1)!, defaultPort);
    }
    if (!entry.contains(':') || entry.contains('::')) {
      return SshEndpoint(entry, defaultPort);
    }
    final parts = entry.split(':');
    final port = int.tryParse(parts.last);
    if (port == null) return SshEndpoint(entry, defaultPort);
    return SshEndpoint(parts.sublist(0, parts.length - 1).join(':'), port);
  }
}
