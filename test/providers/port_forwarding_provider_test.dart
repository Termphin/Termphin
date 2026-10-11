import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/port_forwarding_rule.dart';
import 'package:termphin/providers/port_forwarding_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../support/fixtures.dart';
import '../support/ssh_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSshBackend backend;
  late FakeRemoteAgentService remoteAgentService;
  late SshSessionManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakeSshBackend();
    remoteAgentService = FakeRemoteAgentService(backend);
    manager = SshSessionManager.test(
      remoteAgentService: remoteAgentService,
      serviceFactory: backend.createService,
    );
    await manager.startSession(profileFixture(), sessionId: 'session');
    backend.calls.clear();
  });

  tearDown(() => manager.dispose());

  ProviderContainer createContainer() => ProviderContainer.test(
    overrides: [sshSessionManagerProvider.overrideWithValue(manager)],
  );

  test('loads profile rules as idle entries', () {
    final container = createContainer();
    final rule = forwardingRuleFixture();

    container
        .read(portForwardingProvider('session').notifier)
        .loadProfileRules(profileFixture(portForwardings: [rule]));

    final entry = container
        .read(portForwardingProvider('session'))
        .entries[rule.id];
    expect(entry?.isFromProfile, isTrue);
    expect(entry?.status, TunnelStatus.idle);
  });

  test('starts a tunnel with complete arguments and is idempotent', () async {
    final container = createContainer();
    final notifier = container.read(portForwardingProvider('session').notifier);
    final rule = forwardingRuleFixture(type: ForwardType.remote);

    await notifier.startTunnel(rule, isFromProfile: true);
    await notifier.startTunnel(rule, isFromProfile: true);

    final opens = backend.calls
        .where((call) => call.method == 'tunnelOpen')
        .toList();
    expect(opens, hasLength(1));
    expect(opens.single.arguments, {
      'ruleId': rule.id,
      'ruleType': 'remote',
      'localPort': rule.localPort,
      'remotePort': rule.remotePort,
      'localHost': rule.localHost,
    });
    expect(
      container
          .read(portForwardingProvider('session'))
          .entries[rule.id]
          ?.status,
      TunnelStatus.active,
    );
  });

  test('moves a failed tunnel into the error state', () async {
    final container = createContainer();
    final rule = forwardingRuleFixture();
    backend.tunnelOpenError = Exception('Port busy');

    await container
        .read(portForwardingProvider('session').notifier)
        .startTunnel(rule);

    final entry = container
        .read(portForwardingProvider('session'))
        .entries[rule.id];
    expect(entry?.status, TunnelStatus.error);
    expect(entry?.errorMessage, contains('Port busy'));
  });

  test('stopping a tunnel leaves the rule behind, whoever owns it', () async {
    final container = createContainer();
    final notifier = container.read(portForwardingProvider('session').notifier);
    final profileRule = forwardingRuleFixture(id: 'profile');
    final adhocRule = forwardingRuleFixture(id: 'adhoc');

    await notifier.startTunnel(profileRule, isFromProfile: true);
    await notifier.startTunnel(adhocRule);
    await notifier.stopTunnel(profileRule.id);
    await notifier.stopTunnel(adhocRule.id);

    final entries = container.read(portForwardingProvider('session')).entries;
    expect(entries[profileRule.id]?.status, TunnelStatus.idle);
    expect(entries[adhocRule.id]?.status, TunnelStatus.idle);
    expect(
      backend.calls.where((call) => call.method == 'tunnelClose'),
      hasLength(2),
    );
  });

  test('removing an ad-hoc rule closes its tunnel and drops it', () async {
    final container = createContainer();
    final notifier = container.read(portForwardingProvider('session').notifier);
    final rule = forwardingRuleFixture(id: 'adhoc');

    await notifier.startTunnel(rule);
    await notifier.removeAdhocTunnel(rule.id);

    final entries = container.read(portForwardingProvider('session')).entries;
    expect(entries.containsKey(rule.id), isFalse);
    expect(
      backend.calls.where((call) => call.method == 'tunnelClose'),
      hasLength(1),
    );
  });

  test('a profile rule cannot be removed from the session', () async {
    final container = createContainer();
    final notifier = container.read(portForwardingProvider('session').notifier);
    final rule = forwardingRuleFixture(id: 'profile');

    await notifier.startTunnel(rule, isFromProfile: true);
    await notifier.removeAdhocTunnel(rule.id);

    expect(
      container
          .read(portForwardingProvider('session'))
          .entries[rule.id]
          ?.status,
      TunnelStatus.active,
    );
  });

  test('a second start while the first is still opening is dropped', () async {
    final container = createContainer();
    final notifier = container.read(portForwardingProvider('session').notifier);
    final rule = forwardingRuleFixture();

    await Future.wait([notifier.startTunnel(rule), notifier.startTunnel(rule)]);

    expect(
      backend.calls.where((call) => call.method == 'tunnelOpen'),
      hasLength(1),
    );
  });

  test('starts all idle profile rules but not ad-hoc rules', () async {
    final container = createContainer();
    final notifier = container.read(portForwardingProvider('session').notifier);
    final first = forwardingRuleFixture(id: 'first');
    final second = forwardingRuleFixture(id: 'second');
    final adhoc = forwardingRuleFixture(id: 'adhoc');
    notifier.loadProfileRules(profileFixture(portForwardings: [first, second]));
    notifier.addAdhocTunnel(adhoc);

    await notifier.startAllProfileRules();

    expect(
      backend.calls.where((call) => call.method == 'tunnelOpen'),
      hasLength(2),
    );
    final entries = container.read(portForwardingProvider('session')).entries;
    expect(entries[first.id]?.status, TunnelStatus.active);
    expect(entries[second.id]?.status, TunnelStatus.active);
    expect(entries[adhoc.id]?.status, TunnelStatus.idle);
  });
}
