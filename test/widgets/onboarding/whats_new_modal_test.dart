import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/app/whats_new_service.dart';
import 'package:termphin/services/completion/command_completion.dart';
import 'package:termphin/services/settings/upload_settings.dart';
import 'package:termphin/widgets/onboarding/whats_new_modal.dart';
import 'package:yaml/yaml.dart';

import '../../support/test_app.dart';

const _one = [
  ReleaseHighlight(
    id: 'x',
    version: '1.0.0',
    title: 'Only feature',
    body: 'Body one',
  ),
];

const _two = [
  ReleaseHighlight(
    id: 'first',
    version: '1.0.0',
    title: 'First feature',
    body: 'Body one',
  ),
  ReleaseHighlight(
    id: 'second',
    version: '1.0.0',
    title: 'Second feature',
    body: 'Body two',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t = AppLocale.en.buildSync();

  /// The page on screen, as opposed to the copies a carousel lays out
  /// unpainted behind it to take its height from.
  Finder onPage(String text) =>
      find.descendant(of: find.byType(PageView), matching: find.text(text));

  Future<void> open(WidgetTester tester, List<ReleaseHighlight> highlights) {
    return pumpTestApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showWhatsNewModal(context, highlights),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a single highlight shows no dots and dismisses on the button', (
    tester,
  ) async {
    await open(tester, _one);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Only feature'), findsOneWidget);
    expect(find.text('Body one'), findsOneWidget);
    expect(find.text(t.whatsNew.gotIt), findsOneWidget);
    expect(find.text(t.whatsNew.next), findsNothing);

    await tester.tap(find.text(t.whatsNew.gotIt));
    await tester.pumpAndSettle();
    expect(find.text('Only feature'), findsNothing);
  });

  testWidgets('two highlights group into a carousel paged by the button', (
    tester,
  ) async {
    await open(tester, _two);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(onPage('First feature'), findsOneWidget);
    expect(onPage('Second feature'), findsNothing);
    expect(find.text(t.whatsNew.next), findsOneWidget);

    await tester.tap(find.text(t.whatsNew.next));
    await tester.pumpAndSettle();

    expect(onPage('Second feature'), findsOneWidget);
    expect(find.text(t.whatsNew.next), findsNothing);
    expect(find.text(t.whatsNew.gotIt), findsOneWidget);

    await tester.tap(find.text(t.whatsNew.gotIt));
    await tester.pumpAndSettle();
    expect(find.text('Second feature'), findsNothing);
  });

  testWidgets('swiping back to an earlier page restores the Next button', (
    tester,
  ) async {
    await open(tester, _two);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.whatsNew.next));
    await tester.pumpAndSettle();
    expect(find.text(t.whatsNew.gotIt), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pumpAndSettle();

    expect(onPage('First feature'), findsOneWidget);
    expect(find.text(t.whatsNew.next), findsOneWidget);
    expect(find.text(t.whatsNew.gotIt), findsNothing);
  });

  testWidgets('a short page makes a short card', (tester) async {
    Future<double> cardHeight(List<ReleaseHighlight> highlights) async {
      await open(tester, highlights);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final height = tester
          .getSize(
            find
                .descendant(
                  of: find.byType(Dialog),
                  matching: find.byType(Material),
                )
                .first,
          )
          .height;
      await tester.tap(find.text(t.whatsNew.gotIt));
      await tester.pumpAndSettle();
      return height;
    }

    final short = await cardHeight(_one);
    final long = await cardHeight(const [
      ReleaseHighlight(
        id: 'wordy',
        version: '1.0.0',
        title: 'Only feature',
        body:
            'A body long enough to need several lines of its own, so the card '
            'has to be taller than one carrying a single short sentence. '
            'Which is the whole point: the height follows what is written.',
      ),
    ]);

    expect(short, lessThan(long));
  });

  testWidgets('a page too tall for the ceiling scrolls instead of growing', (
    tester,
  ) async {
    await open(tester, [
      ReleaseHighlight(
        id: 'endless',
        version: '1.0.0',
        title: 'Only feature',
        body: List.filled(60, 'More than fits.').join(' '),
      ),
    ]);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final card = tester.getSize(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );

    expect(card.height, lessThan(screen * 0.75));
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets('a carousel is one height, not one per page', (tester) async {
    await open(tester, _two);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final cardFinder = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first;
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final card = tester.getSize(cardFinder);

    expect(card.height, lessThan(screen * 0.75));
    await tester.tap(find.text(t.whatsNew.next));
    await tester.pumpAndSettle();
    expect(tester.getSize(cardFinder).height, card.height);
  });

  testWidgets('an empty list opens nothing at all', (tester) async {
    await open(tester, const []);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the barrier does not dismiss it', (tester) async {
    await open(tester, _one);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Only feature'), findsOneWidget);
  });

  testWidgets('a missing image degrades to a text-only page', (tester) async {
    await open(tester, const [
      ReleaseHighlight(
        id: 'broken',
        version: '1.0.0',
        title: 'Broken picture',
        body: 'Body',
        image: 'assets/does_not_exist.png',
      ),
    ]);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Broken picture'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('landscape drops the illustration to keep the words', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showWhatsNewModal(context, const [
                  ReleaseHighlight(
                    id: 'landscape',
                    version: '1.0.0',
                    title: 'Landscape feature',
                    body: 'Body',
                    image: 'assets/logo.png',
                  ),
                ]),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Landscape feature'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  group('a setting on the page', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await commandSuggestionsSetting.load();
    });

    testWidgets('is a switch that turns the feature off where it is shown', (
      tester,
    ) async {
      await open(tester, [
        ReleaseHighlight(
          id: 's',
          version: '1.0.0',
          title: 'Suggestions',
          body: 'Body',
          setting: commandSuggestionsSetting.key,
        ),
      ]);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(t.settings.commandSuggestions), findsOneWidget);
      expect(commandSuggestionsSetting.value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(commandSuggestionsSetting.value, isFalse);
    });

    testWidgets('draws nothing for a key that is not on the list', (
      tester,
    ) async {
      await open(tester, const [
        ReleaseHighlight(
          id: 's',
          version: '1.0.0',
          title: 'Suggestions',
          body: 'Body',
          setting: 'no_such_setting',
        ),
      ]);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsNothing);
    });
  });

  testWidgets('a portrait recording is narrowed, not made taller', (
    tester,
  ) async {
    await open(tester, const [
      ReleaseHighlight(
        id: 'gif',
        version: '1.0.0',
        title: 'Recorded',
        body: 'Body',
        image: 'assets/whats_new/groups.png',
        imageAspect: 9 / 16,
      ),
    ]);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(AspectRatio));
    expect(size.height, lessThanOrEqualTo(250));
    expect(size.width / size.height, closeTo(9 / 16, 0.01));
  });

  test('every setting named in whats_new.yaml has a switch to draw', () {
    final doc = loadYaml(File('assets/whats_new.yaml').readAsStringSync());
    final keys = [
      for (final entry in doc as YamlList)
        for (final highlight in (entry['highlights'] as YamlList? ?? []))
          if (highlight['setting'] case final String key) key,
    ];

    expect(keys, isNotEmpty);
    for (final key in keys) {
      expect(whatsNewToggles, contains(key), reason: key);
    }
  });

  group('as an explainer beside a setting', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await commandSuggestionsSetting.load();
      WhatsNewService.instance.debugSetHighlights([
        ReleaseHighlight(
          id: kAutocompleteExplainerId,
          version: 'Unreleased',
          title: 'Autocomplete',
          body: 'Body',
          setting: commandSuggestionsSetting.key,
        ),
      ]);
    });

    tearDown(() => WhatsNewService.instance.debugSetHighlights(null));

    testWidgets('has no announcement label and no switch', (tester) async {
      await pumpTestApp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showFeatureExplainer(context, kAutocompleteExplainerId),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Autocomplete'), findsOneWidget);
      expect(find.text(t.whatsNew.nowAvailable.toUpperCase()), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });
  });

  test('every explainer a setting opens is in whats_new.yaml', () {
    final doc = loadYaml(File('assets/whats_new.yaml').readAsStringSync());
    final ids = [
      for (final entry in doc as YamlList)
        for (final highlight in (entry['highlights'] as YamlList? ?? []))
          highlight['id'],
    ];

    expect(
      ids,
      containsAll([kAutocompleteExplainerId, kFastUploadExplainerId]),
    );
  });
}
