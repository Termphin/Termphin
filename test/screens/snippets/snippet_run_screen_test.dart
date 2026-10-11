import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/snippet.dart';
import 'package:termphin/models/snippet_run.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/snippet_runs_provider.dart';
import 'package:termphin/screens/snippets/snippet_run_screen.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/utils/profile_sort.dart';
import 'package:termphin/widgets/ssh/remote_agent_info_sheet.dart';
import 'package:termphin/widgets/ui/app_dropdown.dart';
import 'package:termphin/widgets/ui/empty_state.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

Snippet _snippet({
  String command = 'uptime',
  Map<String, String> defaults = const {},
}) => Snippet(
  id: 'snip-1',
  name: 'Uptime',
  command: command,
  createdAt: DateTime(2026),
  defaults: defaults,
);

/// Records what a run would have been started with, without dialling anything.
class _StubRuns extends SnippetRunsNotifier {
  Snippet? snippet;
  List<SshProfile>? profiles;
  Map<String, String>? args;

  @override
  List<SnippetRunBatch> build() => [];

  @override
  String start({
    required Snippet snippet,
    required List<SshProfile> profiles,
    Map<String, String> argValues = const {},
  }) {
    this.snippet = snippet;
    this.profiles = profiles;
    args = argValues;
    return 'batch-1';
  }
}

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  Future<(_StubRuns, List<String?>)> pump(
    WidgetTester tester,
    Snippet snippet, {
    List<SshProfile> profiles = const [],
  }) async {
    final stub = _StubRuns();
    final results = <String?>[];
    final container = ProviderContainer.test(
      overrides: [
        snippetRunsProvider.overrideWith(() => stub),
        profilesProvider.overrideWith(() => _StubProfiles(profiles)),
      ],
    );

    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async =>
                  results.add(await showSnippetRunScreen(context, snippet)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      container: container,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (stub, results);
  }

  testWidgets('says so when there is no machine to run on', (tester) async {
    await pump(tester, _snippet());
    expect(find.byType(EmptyStatePanel), findsOneWidget);
    expect(find.text(t.snippets.pickMachinesEmpty), findsOneWidget);
  });

  testWidgets('lists the machines it could run on', (tester) async {
    await pump(
      tester,
      _snippet(),
      profiles: [
        profileFixture(id: 'p1', name: 'Alpha'),
        profileFixture(id: 'p2', name: 'Beta'),
      ],
    );

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('orders machines the way the home screen does, and re-sorts', (
    tester,
  ) async {
    await pump(
      tester,
      _snippet(),
      profiles: [
        profileFixture(
          id: 'p1',
          name: 'Zulu',
          lastConnectedAt: DateTime.utc(2026, 5),
        ),
        profileFixture(
          id: 'p2',
          name: 'Alpha',
          lastConnectedAt: DateTime.utc(2026, 1),
        ),
      ],
    );

    double y(String name) => tester.getTopLeft(find.text(name)).dy;

    expect(y('Zulu'), lessThan(y('Alpha')));

    await tester.tap(find.byType(AppActionDropdown<ProfileSort>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.profiles.sortAZ).last);
    await tester.pumpAndSettle();

    expect(y('Alpha'), lessThan(y('Zulu')));
  });

  testWidgets('will not run until a machine is picked', (tester) async {
    await pump(
      tester,
      _snippet(),
      profiles: [profileFixture(id: 'p1', name: 'Alpha')],
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, t.snippets.runNow(count: 0)),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('counts what has been picked', (tester) async {
    await pump(
      tester,
      _snippet(),
      profiles: [
        profileFixture(id: 'p1', name: 'Alpha'),
        profileFixture(id: 'p2', name: 'Beta'),
      ],
    );

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text(t.snippets.runNow(count: 1)), findsOneWidget);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(find.text(t.snippets.runNow(count: 2)), findsOneWidget);
  });

  testWidgets('picks every machine at once, and puts them all back', (
    tester,
  ) async {
    await pump(
      tester,
      _snippet(),
      profiles: [
        profileFixture(id: 'p1', name: 'Alpha'),
        profileFixture(id: 'p2', name: 'Beta'),
      ],
    );

    await tester.tap(find.text(t.common.selectAll));
    await tester.pumpAndSettle();
    expect(find.text(t.snippets.runNow(count: 2)), findsOneWidget);

    await tester.tap(find.text(t.common.clearSelection));
    await tester.pumpAndSettle();
    expect(find.text(t.snippets.runNow(count: 0)), findsOneWidget);
  });

  testWidgets('select all takes the filtered list, not the hidden rest', (
    tester,
  ) async {
    await pump(
      tester,
      _snippet(),
      profiles: [
        profileFixture(id: 'p1', name: 'Alpha'),
        profileFixture(id: 'p2', name: 'Beta'),
      ],
    );

    await tester.enterText(find.byType(TextField).last, 'Beta');
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(find.text(t.common.selectAll));
    await tester.pumpAndSettle();

    expect(find.text(t.snippets.runNow(count: 1)), findsOneWidget);
  });

  testWidgets('starts the run on exactly what was picked', (tester) async {
    final (stub, results) = await pump(
      tester,
      _snippet(),
      profiles: [
        profileFixture(id: 'p1', name: 'Alpha'),
        profileFixture(id: 'p2', name: 'Beta'),
      ],
    );

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.snippets.runNow(count: 1)));
    await tester.pumpAndSettle();

    expect(stub.profiles!.map((p) => p.id), ['p2']);
    expect(results, ['batch-1']);
  });

  testWidgets('offers a field per placeholder, filled with its default', (
    tester,
  ) async {
    await pump(
      tester,
      _snippet(
        command: 'systemctl restart {{service}}',
        defaults: {'service': 'nginx'},
      ),
      profiles: [profileFixture(id: 'p1', name: 'Alpha')],
    );

    expect(find.text('nginx'), findsOneWidget);
  });

  testWidgets('carries the placeholder values into the run', (tester) async {
    final (stub, _) = await pump(
      tester,
      _snippet(
        command: 'systemctl restart {{service}}',
        defaults: {'service': 'nginx'},
      ),
      profiles: [profileFixture(id: 'p1', name: 'Alpha')],
    );

    await tester.enterText(find.byType(TextField).first, 'postgres');
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.snippets.runNow(count: 1)));
    await tester.pumpAndSettle();

    expect(stub.args, {'service': 'postgres'});
  });

  group('the agent sheet', () {
    testWidgets('explains what the helper does and what it does not', (
      tester,
    ) async {
      await pumpTestApp(tester, Scaffold(body: RemoteAgentInfoSheet(t: t)));
      await tester.pumpAndSettle();

      expect(find.text(t.settings.agentSheetTitle), findsOneWidget);
      expect(find.text(t.settings.agentSheetPointNoNetwork), findsOneWidget);
      expect(find.text(t.settings.agentSheetPointNoRoot), findsOneWidget);
      expect(find.text(t.settings.agentSheetRepoButton), findsOneWidget);
    });
  });
}

class _StubProfiles extends ProfilesNotifier {
  _StubProfiles(this.initial);

  final List<SshProfile> initial;

  @override
  List<SshProfile> build() => initial;
}
