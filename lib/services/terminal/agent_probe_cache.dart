import '../../models/remote_agent_status.dart';
import '../ssh/remote_agent_service.dart';

/// Remembers, per profile, that the Termphin agent on that host was found
/// installed and up to date.
///
/// Every round trip during a connect is one the user watches in the
/// connecting log before a single byte of terminal shows up, and a probe this
/// process already has an answer for is one of them. What this saves is the
/// reconnect storm - the same host attached repeatedly within minutes.
///
/// In memory only, deliberately. A cached probe compares the host against the
/// binary bundled in *this* build, so one that outlived the process could
/// outlive the binary it was compared against and wave through a host that
/// now needs an upgrade. A cold start always probes.
class AgentProbeCache {
  AgentProbeCache({Duration? ttl, DateTime Function()? now})
    : _ttl = ttl ?? _defaultTtl,
      _now = now ?? DateTime.now;

  /// Long enough to cover a run of reconnects, short enough that a binary
  /// removed on the far end is noticed without restarting the app.
  static const Duration _defaultTtl = Duration(minutes: 5);

  final Duration _ttl;
  final DateTime Function() _now;
  final Map<String, _Entry> _entries = {};

  /// A probe good enough to attach on without asking the server again, or
  /// null when the next attach has to find out for itself.
  DartRemoteAgentStatus? get(String profileId) {
    final cached = _entries[profileId];
    if (cached == null) return null;
    if (_now().difference(cached.at) > _ttl) {
      _entries.remove(profileId);
      return null;
    }
    return cached.status;
  }

  /// Only a host that is already installed and current is worth caching:
  /// every other state means `RemoteAgentService.ensureForAttach` has real
  /// work to do, and it needs a current picture to do it. Storing one of
  /// those would skip the work rather than the probe.
  void put(String profileId, DartRemoteAgentStatus status) {
    if (!status.usable ||
        status.publicStatus.state != RemoteAgentState.current) {
      _entries.remove(profileId);
      return;
    }
    _entries[profileId] = _Entry(status, _now());
  }

  void forget(String profileId) => _entries.remove(profileId);

  void clear() => _entries.clear();
}

class _Entry {
  const _Entry(this.status, this.at);

  final DartRemoteAgentStatus status;
  final DateTime at;
}
