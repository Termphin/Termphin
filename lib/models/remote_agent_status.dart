enum RemoteAgentState {
  unsupported,
  missing,
  repair,
  current,
  updateAvailable,
  newer;

  static RemoteAgentState fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => RemoteAgentState.missing,
  );
}

class RemoteAgentStatus {
  const RemoteAgentStatus({
    required this.state,
    required this.supported,
    this.architecture,
    this.operatingSystem,
    this.bundledVersion,
    this.bundledSha256,
    this.bundledProtocol,
    this.remoteVersion,
    this.remoteSha256,
    this.remoteProtocol,
  });

  final RemoteAgentState state;
  final bool supported;
  final String? architecture;
  final String? operatingSystem;
  final String? bundledVersion;
  final String? bundledSha256;
  final int? bundledProtocol;
  final String? remoteVersion;
  final String? remoteSha256;
  final int? remoteProtocol;

  bool get updateAvailable => state == RemoteAgentState.updateAvailable;

  factory RemoteAgentStatus.fromMap(Map<Object?, Object?> map) =>
      RemoteAgentStatus(
        state: RemoteAgentState.fromName(map['state'] as String?),
        supported: map['supported'] as bool? ?? false,
        architecture: map['architecture'] as String?,
        operatingSystem: map['operatingSystem'] as String?,
        bundledVersion: map['bundledVersion'] as String?,
        bundledSha256: map['bundledSha256'] as String?,
        bundledProtocol: map['bundledProtocol'] as int?,
        remoteVersion: map['remoteVersion'] as String?,
        remoteSha256: map['remoteSha256'] as String?,
        remoteProtocol: map['remoteProtocol'] as int?,
      );

  factory RemoteAgentStatus.fromJson(Map<String, dynamic> json) =>
      RemoteAgentStatus.fromMap(json);

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'supported': supported,
    'architecture': architecture,
    'operatingSystem': operatingSystem,
    'bundledVersion': bundledVersion,
    'bundledSha256': bundledSha256,
    'bundledProtocol': bundledProtocol,
    'remoteVersion': remoteVersion,
    'remoteSha256': remoteSha256,
    'remoteProtocol': remoteProtocol,
  };
}
