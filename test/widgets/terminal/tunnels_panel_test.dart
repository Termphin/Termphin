import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/port_forwarding_rule.dart';
import 'package:termphin/providers/port_forwarding_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/terminal/tunnels_panel.dart';
import 'package:termphin/widgets/ui/empty_state.dart';

import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

/// The `portForwardingProvider` family is auto-disposed, so a seed written
/// before the panel mounts would be thrown away with the provider between
/// the two unless something keeps a listener on it.
void main() {
  final t = AppLocale.en.buildSync();

  late FakeSshBackend backend;
  late SshSessionManager manager;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    backend = FakeSshBackend();
    manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    await manager.startSession(profileFixture(), sessionId: 'session');
    backend.calls.clear();
    container = ProviderContainer.test(
      overrides: [sshSessionManagerProvider.overrideWithValue(manager)],
    );
    addTearDown(
      container.listen(portForwardingProvider('session'), (_, _) {}).close,
    );
  });

  tearDown(() => manager.dispose());

  PortForwardingNotifier notifier() =>
      container.read(portForwardingProvider('session').notifier);

  Map<String, TunnelEntry> entries() =>
      container.read(portForwardingProvider('session')).entries;

  TunnelEntry entryFor(String id) => entries()[id]!;

  /// The panel is always shown in a bottom sheet, which is where its
  /// `ListTile`s get the Material they need.
  Future<void> pump(WidgetTester tester) async {
    await pumpTestApp(
      tester,
      const Scaffold(body: TunnelsPanel(sessionId: 'session')),
      container: container,
    );
    await tester.pumpAndSettle();
  }

  Switch switchFor(WidgetTester tester, String name) => tester.widget<Switch>(
    find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
      matching: find.byType(Switch),
    ),
  );

  Future<void> tapSwitch(WidgetTester tester, String name) async {
    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('says so when the session has no rules', (tester) async {
    await pump(tester);
    expect(find.byType(EmptyStateHint), findsOneWidget);
    expect(find.text(t.portForwarding.noRulesYet), findsOneWidget);
    expect(find.text(t.portForwarding.addTunnel), findsOneWidget);
  });

  testWidgets('shows a profile rule under its own heading', (tester) async {
    notifier().loadProfileRules(
      profileFixture(portForwardings: [forwardingRuleFixture()]),
    );
    await pump(tester);

    expect(find.text(t.portForwarding.profileRules.toUpperCase()), findsOne);
    expect(find.text('Database'), findsOneWidget);
    expect(find.byType(EmptyStateHint), findsNothing);
  });

  testWidgets('a local rule reads device port to server port', (tester) async {
    notifier().loadProfileRules(
      profileFixture(
        portForwardings: [
          forwardingRuleFixture(
            type: ForwardType.local,
            localPort: 15432,
            remotePort: 5432,
          ),
        ],
      ),
    );
    await pump(tester);

    expect(find.text(t.portForwarding.localForward), findsOneWidget);
    expect(find.text(':15432'), findsOneWidget);
    expect(find.text(':5432'), findsOneWidget);
    expect(find.text(t.portForwarding.arrowDevice), findsOneWidget);
  });

  testWidgets('a remote rule reads the other way round', (tester) async {
    notifier().loadProfileRules(
      profileFixture(
        portForwardings: [
          forwardingRuleFixture(
            type: ForwardType.remote,
            localPort: 3000,
            remotePort: 8080,
          ),
        ],
      ),
    );
    await pump(tester);

    expect(find.text(t.portForwarding.remoteForward), findsOneWidget);
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .toList();
    expect(
      labels.indexOf(t.portForwarding.arrowServer),
      lessThan(labels.indexOf(t.portForwarding.arrowDevice)),
    );
    expect(find.text(':8080'), findsOneWidget);
    expect(find.text(':3000'), findsOneWidget);
  });

  testWidgets('a profile rule starts idle and its switch is off', (
    tester,
  ) async {
    notifier().loadProfileRules(
      profileFixture(portForwardings: [forwardingRuleFixture()]),
    );
    await pump(tester);

    expect(entryFor('tunnel-1').status, TunnelStatus.idle);
    expect(switchFor(tester, 'Database').value, isFalse);
  });

  testWidgets('the switch starts an idle tunnel and stops an active one', (
    tester,
  ) async {
    notifier().loadProfileRules(
      profileFixture(portForwardings: [forwardingRuleFixture()]),
    );
    await pump(tester);

    await tapSwitch(tester, 'Database');
    expect(entryFor('tunnel-1').status, TunnelStatus.active);
    expect(switchFor(tester, 'Database').value, isTrue);

    await tapSwitch(tester, 'Database');
    expect(entryFor('tunnel-1').status, TunnelStatus.idle);
    expect(switchFor(tester, 'Database').value, isFalse);
  });

  testWidgets('a profile rule cannot be deleted, only stopped', (tester) async {
    notifier().loadProfileRules(
      profileFixture(portForwardings: [forwardingRuleFixture()]),
    );
    await pump(tester);

    expect(find.byTooltip(t.common.delete), findsNothing);
  });

  testWidgets('an ad-hoc tunnel is listed with a delete button', (
    tester,
  ) async {
    notifier().addAdhocTunnel(
      forwardingRuleFixture(id: 'adhoc-1', name: 'Scratch'),
    );
    await pump(tester);

    expect(find.text('Scratch'), findsOneWidget);
    expect(find.byTooltip(t.common.delete), findsOneWidget);
    expect(
      find.text(t.portForwarding.profileRules.toUpperCase()),
      findsNothing,
    );
  });

  testWidgets('deleting an ad-hoc tunnel takes it off the list', (
    tester,
  ) async {
    notifier().addAdhocTunnel(
      forwardingRuleFixture(id: 'adhoc-1', name: 'Scratch'),
    );
    await pump(tester);
    await tapSwitch(tester, 'Scratch');
    expect(entryFor('adhoc-1').status, TunnelStatus.active);

    await tester.tap(find.byTooltip(t.common.delete));
    await tester.pumpAndSettle();
    expect(entries()['adhoc-1'], isNull);
    expect(find.text('Scratch'), findsNothing);
  });

  testWidgets('switching an ad-hoc tunnel off keeps the rule', (tester) async {
    notifier().addAdhocTunnel(
      forwardingRuleFixture(id: 'adhoc-1', name: 'Scratch'),
    );
    await pump(tester);
    await tapSwitch(tester, 'Scratch');
    await tapSwitch(tester, 'Scratch');

    expect(entryFor('adhoc-1').status, TunnelStatus.idle);
    expect(find.text('Scratch'), findsOneWidget);
  });

  testWidgets('a refused tunnel says why, not just that it failed', (
    tester,
  ) async {
    backend.tunnelOpenError = Exception(
      'Server refused remote forwarding on port 8080.',
    );
    notifier().addAdhocTunnel(
      forwardingRuleFixture(id: 'adhoc-1', name: 'Scratch'),
    );
    await pump(tester);
    await tapSwitch(tester, 'Scratch');

    expect(entryFor('adhoc-1').status, TunnelStatus.error);
    expect(find.text(t.portForwarding.statusError), findsOneWidget);
    expect(
      find.text('Server refused remote forwarding on port 8080.'),
      findsOneWidget,
    );
  });

  testWidgets('an ad-hoc rule can be edited in place', (tester) async {
    notifier().addAdhocTunnel(
      forwardingRuleFixture(id: 'adhoc-1', name: 'Scratch'),
    );
    await pump(tester);

    await tester.tap(find.text('Scratch'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(0)).controller?.text, 'Scratch');

    await tester.enterText(fields.at(0), 'Renamed');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, t.common.save));
    await tester.pumpAndSettle();

    expect(entries().length, 1);
    expect(entryFor('adhoc-1').rule.name, 'Renamed');
    expect(find.text('Renamed'), findsOneWidget);
  });

  testWidgets('a profile rule cannot be edited from the session', (
    tester,
  ) async {
    notifier().loadProfileRules(
      profileFixture(portForwardings: [forwardingRuleFixture()]),
    );
    await pump(tester);

    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Database'), matching: find.byType(ListTile)),
    );
    expect(tile.onTap, isNull);
  });

  testWidgets('lists profile rules above ad-hoc ones', (tester) async {
    notifier().loadProfileRules(
      profileFixture(
        portForwardings: [forwardingRuleFixture(name: 'FromProfile')],
      ),
    );
    notifier().addAdhocTunnel(
      forwardingRuleFixture(id: 'adhoc-1', name: 'Adhoc'),
    );
    await pump(tester);

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .toList();
    expect(names.indexOf('FromProfile'), lessThan(names.indexOf('Adhoc')));
  });

  testWidgets('orders rules by when they were made', (tester) async {
    notifier().addAdhocTunnel(
      forwardingRuleFixture(
        id: 'second',
        name: 'Second',
        createdAt: DateTime(2026, 2, 1),
      ),
    );
    notifier().addAdhocTunnel(
      forwardingRuleFixture(
        id: 'first',
        name: 'First',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await pump(tester);

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .toList();
    expect(names.indexOf('First'), lessThan(names.indexOf('Second')));
  });
}
