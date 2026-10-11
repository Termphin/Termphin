import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/backup/backup_export_screen.dart';
import 'package:termphin/widgets/ui/backup_action_bar.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  SwitchListTile tile(WidgetTester tester, String title) =>
      tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SwitchListTile),
        ),
      );

  Future<void> toggle(WidgetTester tester, String title) async {
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(SwitchListTile),
        ),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapExport(WidgetTester tester) async {
    await tester.tap(find.text(t.exportScreen.exportButton));
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester) async {
    await pumpTestApp(tester, const BackupExportScreen());
    await tester.pumpAndSettle();
  }

  group('what a backup carries by default', () {
    testWidgets('leaves every secret out until it is asked for', (
      tester,
    ) async {
      await pump(tester);

      expect(tile(tester, t.exportScreen.includePasswords).value, isFalse);
      expect(tile(tester, t.exportScreen.includeInlineKeys).value, isFalse);
    });

    testWidgets('includes the harmless parts', (tester) async {
      await pump(tester);

      expect(tile(tester, t.exportScreen.includeSshProfiles).value, isTrue);
      expect(
        tile(tester, t.exportScreen.includeTerminalSettings).value,
        isTrue,
      );
      expect(tile(tester, t.exportScreen.includeAppPreferences).value, isTrue);
    });
  });

  group('the sensitive warning', () {
    testWidgets('is up from the start, since keys are included by default', (
      tester,
    ) async {
      await pump(tester);
      expect(tile(tester, t.exportScreen.includeSshKeys).value, isTrue);
      expect(find.text(t.exportScreen.sensitiveWarning), findsOneWidget);
    });

    testWidgets('goes away once nothing sensitive is selected', (tester) async {
      await pump(tester);
      await toggle(tester, t.exportScreen.includeSshKeys);
      expect(find.text(t.exportScreen.sensitiveWarning), findsNothing);
    });

    testWidgets('comes back for passwords alone', (tester) async {
      await pump(tester);
      await toggle(tester, t.exportScreen.includeSshKeys);
      expect(find.text(t.exportScreen.sensitiveWarning), findsNothing);

      await toggle(tester, t.exportScreen.includePasswords);
      expect(find.text(t.exportScreen.sensitiveWarning), findsOneWidget);
    });

    testWidgets('comes back for inline private keys alone', (tester) async {
      await pump(tester);
      await toggle(tester, t.exportScreen.includeSshKeys);
      await toggle(tester, t.exportScreen.includeInlineKeys);
      expect(find.text(t.exportScreen.sensitiveWarning), findsOneWidget);
    });
  });

  group('secrets are gated behind the profiles they belong to', () {
    testWidgets('passwords and inline keys cannot be set without profiles', (
      tester,
    ) async {
      await pump(tester);
      await toggle(tester, t.exportScreen.includeSshProfiles);

      expect(tile(tester, t.exportScreen.includePasswords).onChanged, isNull);
      expect(tile(tester, t.exportScreen.includeInlineKeys).onChanged, isNull);
    });

    testWidgets('turning profiles off turns the secrets off with them', (
      tester,
    ) async {
      await pump(tester);
      await toggle(tester, t.exportScreen.includePasswords);
      await toggle(tester, t.exportScreen.includeInlineKeys);
      expect(tile(tester, t.exportScreen.includePasswords).value, isTrue);
      expect(tile(tester, t.exportScreen.includeInlineKeys).value, isTrue);

      await toggle(tester, t.exportScreen.includeSshProfiles);
      expect(tile(tester, t.exportScreen.includePasswords).value, isFalse);
      expect(tile(tester, t.exportScreen.includeInlineKeys).value, isFalse);

      await toggle(tester, t.exportScreen.includeSshProfiles);
      expect(tile(tester, t.exportScreen.includePasswords).value, isFalse);
      expect(tile(tester, t.exportScreen.includeInlineKeys).value, isFalse);
    });

    testWidgets('standalone SSH keys are not gated by profiles', (
      tester,
    ) async {
      await pump(tester);
      await toggle(tester, t.exportScreen.includeSshProfiles);
      expect(tile(tester, t.exportScreen.includeSshKeys).onChanged, isNotNull);
      expect(tile(tester, t.exportScreen.includeSshKeys).value, isTrue);
    });
  });

  testWidgets('keeps the export button out of the scroll', (tester) async {
    await pump(tester);

    final bar = find.byType(BackupActionBar);
    expect(bar, findsOneWidget);
    expect(
      find.ancestor(of: bar, matching: find.byType(Scrollable)),
      findsNothing,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text(t.exportScreen.exportButton), findsOneWidget);
  });

  group('the export button', () {
    ElevatedButton exportButton(WidgetTester tester) =>
        tester.widget<ElevatedButton>(
          find.ancestor(
            of: find.text(t.exportScreen.exportButton),
            matching: find.byType(ElevatedButton),
          ),
        );

    testWidgets('is dead once nothing is selected', (tester) async {
      await pump(tester);
      for (final section in [
        t.exportScreen.includeSshProfiles,
        t.exportScreen.includeSshKeys,
        t.exportScreen.includeSnippets,
        t.exportScreen.includeTerminalSettings,
        t.exportScreen.includeAppPreferences,
      ]) {
        await toggle(tester, section);
      }

      expect(exportButton(tester).onPressed, isNull);
    });

    testWidgets('comes back with a single section', (tester) async {
      await pump(tester);
      for (final section in [
        t.exportScreen.includeSshProfiles,
        t.exportScreen.includeSshKeys,
        t.exportScreen.includeSnippets,
        t.exportScreen.includeTerminalSettings,
        t.exportScreen.includeAppPreferences,
      ]) {
        await toggle(tester, section);
      }
      await toggle(tester, t.exportScreen.includeSnippets);

      expect(exportButton(tester).onPressed, isNotNull);
    });
  });

  group('passphrase protection', () {
    testWidgets('hides its fields until it is turned on', (tester) async {
      await pump(tester);
      expect(find.text(t.exportScreen.passphraseLabel), findsNothing);

      await toggle(tester, t.exportScreen.encryptTitle);
      expect(find.text(t.exportScreen.passphraseLabel), findsOneWidget);
      expect(find.text(t.exportScreen.passphraseConfirmLabel), findsOneWidget);
    });

    testWidgets('replaces the plaintext warning', (tester) async {
      await pump(tester);
      expect(find.text(t.exportScreen.sensitiveWarning), findsOneWidget);

      await toggle(tester, t.exportScreen.encryptTitle);
      expect(find.text(t.exportScreen.sensitiveWarning), findsNothing);
    });

    testWidgets('refuses two passphrases that disagree', (tester) async {
      await pump(tester);
      await toggle(tester, t.exportScreen.encryptTitle);
      await tester.enterText(
        find.byType(TextField).first,
        'correct horse battery',
      );
      await tester.enterText(find.byType(TextField).last, 'something else');
      await tapExport(tester);

      expect(find.text(t.exportScreen.passphraseMismatch), findsOneWidget);
    });

    testWidgets('refuses one too short to be worth having', (tester) async {
      await pump(tester);
      await toggle(tester, t.exportScreen.encryptTitle);
      await tester.enterText(find.byType(TextField).first, 'short');
      await tester.enterText(find.byType(TextField).last, 'short');
      await tapExport(tester);

      expect(find.text(t.exportScreen.passphraseTooShort), findsOneWidget);
    });
  });
}
