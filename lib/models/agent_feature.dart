import '../i18n/strings.g.dart';
import '../services/app/version_compare.dart';

/// Something a session can do only when the agent master serving it is new
/// enough.
///
/// A master keeps the version it started with until the session ends -
/// installing a newer agent changes new sessions, and since 0.16.0 moves
/// running ones over in place, but a master from before that cannot move.
/// Each feature names the first master that has it, so a session can say
/// which of them it is missing.
enum AgentFeature {
  longCommandNotice('0.15.0'),
  pushOpensSession('0.15.0'),
  inPlaceUpdates('0.16.0'),
  wentQuietNotice('0.17.0');

  const AgentFeature(this.since);

  /// The first agent version with this feature.
  final String since;

  String label(Translations t) => switch (this) {
    AgentFeature.longCommandNotice => t.agentFeatures.longCommandNotice,
    AgentFeature.pushOpensSession => t.agentFeatures.pushOpensSession,
    AgentFeature.inPlaceUpdates => t.agentFeatures.inPlaceUpdates,
    AgentFeature.wentQuietNotice => t.agentFeatures.wentQuietNotice,
  };

  /// What a session served by a master of [masterVersion] cannot do. A
  /// null version is a master from before masters said theirs, which has
  /// none of these.
  static List<AgentFeature> missingFor(String? masterVersion) => [
    for (final feature in values)
      if (masterVersion == null ||
          !isReleasedVersion(masterVersion) ||
          compareVersions(masterVersion, feature.since) < 0)
        feature,
  ];
}
