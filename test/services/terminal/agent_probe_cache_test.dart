import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/models/remote_agent_status.dart';
import 'package:termphin/services/ssh/remote_agent_service.dart';
import 'package:termphin/services/terminal/agent_probe_cache.dart';

DartRemoteAgentStatus statusFixture({
  RemoteAgentState state = RemoteAgentState.current,
  String? binaryPath = '/home/deploy/.termphin/termphin-agent',
}) => DartRemoteAgentStatus(
  publicStatus: RemoteAgentStatus(
    state: state,
    supported: true,
    remoteVersion: '1.0.0',
    remoteProtocol: 1,
  ),
  binaryPath: binaryPath,
);

void main() {
  test('a cached probe comes back', () {
    final cache = AgentProbeCache();
    cache.put('profile-1', statusFixture());
    expect(cache.get('profile-1'), isNotNull);
  });

  test('a host never probed is a miss, not an answer', () {
    expect(AgentProbeCache().get('profile-1'), isNull);
  });

  test('a probe past its time to live is dropped rather than trusted', () {
    var clock = DateTime(2026, 1, 1, 12);
    final cache = AgentProbeCache(
      ttl: const Duration(minutes: 5),
      now: () => clock,
    );
    cache.put('profile-1', statusFixture());

    clock = clock.add(const Duration(minutes: 4));
    expect(cache.get('profile-1'), isNotNull);

    clock = clock.add(const Duration(minutes: 2));
    expect(cache.get('profile-1'), isNull);
  });

  test('a host that needs an update is not cached', () {
    final cache = AgentProbeCache();
    cache.put(
      'profile-1',
      statusFixture(state: RemoteAgentState.updateAvailable),
    );
    expect(cache.get('profile-1'), isNull);
  });

  test('a probe with no binary on the far end is not cached', () {
    final cache = AgentProbeCache();
    cache.put('profile-1', statusFixture(binaryPath: null));
    expect(cache.get('profile-1'), isNull);
  });

  test('caching a bad probe clears whatever was cached before', () {
    final cache = AgentProbeCache();
    cache.put('profile-1', statusFixture());
    cache.put('profile-1', statusFixture(state: RemoteAgentState.missing));
    expect(cache.get('profile-1'), isNull);
  });
}
