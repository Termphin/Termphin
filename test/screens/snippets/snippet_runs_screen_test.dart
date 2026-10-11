import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/snippet_run.dart';
import 'package:termphin/providers/snippet_runs_provider.dart';
import 'package:termphin/screens/snippets/snippet_runs_screen.dart';
import 'package:termphin/services/settings/anonymize_setting.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/widgets/snippets/snippet_run_output.dart';
import 'package:termphin/widgets/ui/empty_state.dart';

import '../../support/test_app.dart';

SnippetRun _run({
  String id = 'run-1',
  String profileName = 'Production',
  SnippetRunStatus status = SnippetRunStatus.running,
  int? exitCode,
  String? error,
  String output = '',
}) => SnippetRun(
  id: id,
  profileId: 'p1',
  profileName: profileName,
  sessionId: 'session-1',
  status: status,
  exitCode: exitCode,
  error: error,
  output: output,
);

SnippetRunBatch _batch({
  String id = 'batch-1',
  String snippetName = 'Uptime',
  List<SnippetRun>? runs,
}) => SnippetRunBatch(
  id: id,
  snippetName: snippetName,
  command: 'uptime',
  startedAt: DateTime(2026, 4, 1),
  runs: runs ?? [_run()],
);

/// Stands in for the real notifier so a screen test does not have to start
/// sessions to get a history on screen.
class _StubRuns extends SnippetRunsNotifier {
  _StubRuns(this.initial);

  final List<SnippetRunBatch> initial;
  final List<String> forgotten = [];

  @override
  List<SnippetRunBatch> build() => initial;

  @override
  void forget(String batchId) {
    forgotten.add(batchId);
    state = state.where((batch) => batch.id != batchId).toList();
  }
}

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  Future<_StubRuns> pump(
    WidgetTester tester,
    List<SnippetRunBatch> batches,
  ) async {
    final stub = _StubRuns(batches);
    final container = ProviderContainer.test(
      overrides: [snippetRunsProvider.overrideWith(() => stub)],
    );
    await pumpTestApp(tester, const SnippetRunsScreen(), container: container);
    await tester.pumpAndSettle();
    return stub;
  }

  testWidgets('says so when nothing has been run', (tester) async {
    await pump(tester, []);
    expect(find.byType(EmptyStatePanel), findsOneWidget);
    expect(find.text(t.snippets.runsEmpty), findsOneWidget);
  });

  testWidgets('shows a card per batch and a row per machine', (tester) async {
    await pump(tester, [
      _batch(
        runs: [
          _run(id: 'a', profileName: 'Alpha'),
          _run(id: 'b', profileName: 'Beta'),
        ],
      ),
    ]);

    expect(find.text('Uptime'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('names the outcome of each run', (tester) async {
    await pump(tester, [
      _batch(
        runs: [
          _run(
            id: 'ok',
            profileName: 'Good',
            status: SnippetRunStatus.succeeded,
            exitCode: 0,
          ),
          _run(
            id: 'bad',
            profileName: 'Bad',
            status: SnippetRunStatus.failed,
            exitCode: 3,
          ),
        ],
      ),
    ]);

    expect(find.text(t.snippets.runSucceeded), findsOneWidget);
    expect(find.text(t.snippets.runFailed(code: 3)), findsOneWidget);
  });

  testWidgets('shows the reason a run never got going', (tester) async {
    await pump(tester, [
      _batch(
        runs: [
          _run(
            status: SnippetRunStatus.error,
            error: 'Host unreachable: no route',
          ),
        ],
      ),
    ]);

    expect(find.text('Host unreachable: no route'), findsOneWidget);
  });

  testWidgets('shows what the host printed', (tester) async {
    await pump(tester, [
      _batch(runs: [_run(output: 'load average: 0.10')]),
    ]);

    expect(find.byType(SnippetRunOutput), findsOneWidget);
    expect(find.text('load average: 0.10'), findsOneWidget);
  });

  testWidgets('follows a live run and stops following a finished one', (
    tester,
  ) async {
    await pump(tester, [
      _batch(
        id: 'live',
        runs: [
          _run(id: 'r1', status: SnippetRunStatus.running, output: 'going'),
        ],
      ),
      _batch(
        id: 'done',
        snippetName: 'Finished',
        runs: [
          _run(
            id: 'r2',
            status: SnippetRunStatus.succeeded,
            exitCode: 0,
            output: 'done',
          ),
        ],
      ),
    ]);

    await tester.tap(find.text(t.snippets.runSucceeded));
    await tester.pumpAndSettle();

    final follows = tester
        .widgetList<SnippetRunOutput>(find.byType(SnippetRunOutput))
        .map((w) => w.follow)
        .toList();
    expect(follows, [true, false]);
  });

  testWidgets('a run that worked keeps its output folded away', (tester) async {
    await pump(tester, [
      _batch(
        runs: [
          _run(
            id: 'ok',
            status: SnippetRunStatus.succeeded,
            exitCode: 0,
            output: 'done',
          ),
        ],
      ),
    ]);

    expect(find.byType(SnippetRunOutput), findsNothing);

    await tester.tap(find.text(t.snippets.runSucceeded));
    await tester.pumpAndSettle();

    expect(find.byType(SnippetRunOutput), findsOneWidget);
  });

  testWidgets('forgetting a batch asks first, then takes it off the list', (
    tester,
  ) async {
    final stub = await pump(tester, [
      _batch(id: 'batch-1'),
      _batch(id: 'batch-2', snippetName: 'Disk'),
    ]);

    await tester.tap(find.byTooltip(t.snippets.moreActions).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.snippets.runForget).last);
    await tester.pumpAndSettle();

    expect(stub.forgotten, isEmpty);

    await tester.tap(find.text(t.snippets.runForget).last);
    await tester.pumpAndSettle();

    expect(stub.forgotten, ['batch-1']);
    expect(find.text('Uptime'), findsNothing);
    expect(find.text('Disk'), findsOneWidget);
  });

  testWidgets('hides the machine name when anonymize is on', (tester) async {
    await anonymizeSetting.set(true);
    await pump(tester, [
      _batch(runs: [_run(profileName: 'Production')]),
    ]);

    expect(find.text('Production'), findsNothing);
  });
}
