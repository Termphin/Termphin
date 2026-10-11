import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/groups/groups_screen.dart';
import 'package:termphin/screens/settings/editor_settings_screen.dart';
import 'package:termphin/screens/settings/settings_screen.dart';
import 'package:termphin/screens/settings/toolbar_profiles_screen.dart';
import 'package:termphin/services/analytics/analytics_service.dart';
import 'package:termphin/services/app/whats_new_service.dart';
import 'package:termphin/services/completion/command_completion.dart';
import 'package:termphin/services/security/lock_service.dart';
import 'package:termphin/services/settings/anonymize_setting.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/floating_dock_settings.dart';
import 'package:termphin/services/settings/sftp_settings.dart';
import 'package:termphin/services/settings/tab_bar_settings.dart';
import 'package:termphin/services/settings/theme_settings.dart';
import 'package:termphin/services/settings/toolbar_layout.dart';
import 'package:termphin/services/settings/upload_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/ui/section_header.dart';

import '../../support/secure_storage_channel.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    mockSecureStorage();
    PackageInfo.setMockInitialValues(
      appName: 'Termphin',
      packageName: 'termphin',
      version: '1.4.2',
      buildNumber: '57',
      buildSignature: '',
    );
    await loadAppSettings();
  });

  /// The screen's load asks the platform several questions - biometrics,
  /// battery, notifications, package info - and those replies only arrive on
  /// the real event loop. Under the fake clock alone the spinner never goes
  /// away and `pumpAndSettle` spins on it.
  Future<void> pump(WidgetTester tester) async {
    await pumpTestApp(tester, const SettingsScreen());
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();
  }

  SwitchListTile switchFor(WidgetTester tester, String title) =>
      tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SwitchListTile),
        ),
      );

  Future<void> toggle(WidgetTester tester, String title) async {
    final finder = find.descendant(
      of: find.ancestor(
        of: find.text(title),
        matching: find.byType(SwitchListTile),
      ),
      matching: find.byType(Switch),
    );
    await tester.scrollUntilVisible(finder, 120);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  group('the shape of the screen', () {
    testWidgets('groups its rows under headings', (tester) async {
      await pump(tester);

      final headings = <String>{};
      for (var i = 0; i < 30; i++) {
        headings.addAll(
          tester
              .widgetList<SectionHeader>(find.byType(SectionHeader))
              .map((h) => h.text),
        );
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }

      expect(
        headings,
        containsAll(<String>[
          t.settings.appearance,
          t.settings.terminal,
          t.settings.sftp,
          t.settings.connection,
          t.settings.security,
          t.settings.privacy,
          t.settings.analytics,
          t.settings.about,
        ]),
      );
    });

    testWidgets('shows the version it was built as', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.textContaining('1.4.2'));
      expect(find.textContaining('1.4.2 (57)'), findsOneWidget);
    });

    testWidgets('links to the terminal appearance screen rather than '
        'repeating its settings', (tester) async {
      await pump(tester);
      expect(find.text(t.settings.terminalAppearance), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });
  });

  group('the SFTP section', () {
    testWidgets('leads to the text editor settings', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.textEditor));
      await tester.tap(find.text(t.settings.textEditor));
      await tester.pumpAndSettle();

      expect(find.byType(EditorSettingsScreen), findsOneWidget);
    });

    testWidgets('the hidden files switch is the browser\'s setting', (
      tester,
    ) async {
      await pump(tester);
      await toggle(tester, t.settings.sftpShowHidden);

      expect(sftpShowHiddenSetting.value, isTrue);
    });

    testWidgets('the follow-the-terminal switch turns it off', (tester) async {
      await sftpFollowTerminalSetting.load();
      await pump(tester);
      await toggle(tester, t.settings.sftpFollowTerminal);

      expect(sftpFollowTerminalSetting.value, isFalse);
    });
  });

  group('the remote agent switch', () {
    testWidgets('starts from what is stored', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.remoteAgentToggle));
      expect(
        switchFor(tester, t.settings.remoteAgentToggle).value,
        remoteAgentSetting.value,
      );
    });

    testWidgets('writes straight through to the setting', (tester) async {
      await pump(tester);
      final before = remoteAgentSetting.value;

      await toggle(tester, t.settings.remoteAgentToggle);

      expect(remoteAgentSetting.value, !before);
      expect(switchFor(tester, t.settings.remoteAgentToggle).value, !before);
    });
  });

  group('the on-screen controls', () {
    testWidgets('moves the tabs to the bottom and back', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.tabsAtBottom));
      expect(switchFor(tester, t.settings.tabsAtBottom).value, isFalse);

      await toggle(tester, t.settings.tabsAtBottom);
      expect(tabBarPositionSetting.value, TabBarPosition.bottom);
      expect(switchFor(tester, t.settings.tabsAtBottom).value, isTrue);

      await toggle(tester, t.settings.tabsAtBottom);
      expect(tabBarPositionSetting.value, TabBarPosition.top);
    });

    testWidgets('each feature has its own switch', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.keyToolbar));

      expect(switchFor(tester, t.settings.keyToolbar).value, isTrue);
      expect(switchFor(tester, t.settings.actionDock).value, isTrue);

      await toggle(tester, t.settings.keyToolbar);

      expect(toolbarSettings.enabled.value, isFalse);
      expect(floatingDockSettings.enabled.value, isTrue);
      expect(switchFor(tester, t.settings.actionDock).value, isTrue);
    });

    testWidgets('the layout row only exists under a switch that is on', (
      tester,
    ) async {
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.keyToolbar));

      expect(find.text(t.settings.toolbarLayout), findsOneWidget);
      expect(find.text(t.settings.actionDockLayout), findsOneWidget);

      await toggle(tester, t.settings.keyToolbar);
      expect(find.text(t.settings.toolbarLayout), findsNothing);
      expect(find.text(t.settings.actionDockLayout), findsOneWidget);

      await toggle(tester, t.settings.actionDock);
      expect(find.text(t.settings.actionDockLayout), findsNothing);
    });

    testWidgets('switching a feature back on brings its layout row back', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'terminal_toolbar_enabled': false,
      });
      SharedPreferences.resetStatic();
      await loadAppSettings();
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.keyToolbar));

      expect(find.text(t.settings.toolbarLayout), findsNothing);

      await toggle(tester, t.settings.keyToolbar);

      expect(toolbarSettings.enabled.value, isTrue);
      expect(find.text(t.settings.toolbarLayout), findsOneWidget);
    });

    testWidgets('the layout row opens the editor', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.toolbarLayout));
      await tester.tap(find.text(t.settings.toolbarLayout));
      await tester.pumpAndSettle();

      expect(find.byType(ToolbarProfilesScreen), findsOneWidget);
    });
  });

  testWidgets('the groups row opens the groups screen', (tester) async {
    await pump(tester);
    await scrollTo(tester, find.text(t.groups.title));
    await tester.tap(find.text(t.groups.title));
    await tester.pumpAndSettle();

    expect(find.byType(GroupsScreen), findsOneWidget);
  });

  group('biometric unlock is gated behind the PIN', () {
    testWidgets('is off and says to set a PIN first', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.biometricUnlock));

      expect(switchFor(tester, t.settings.biometricUnlock).value, isFalse);
      expect(find.text(t.settings.enablePinFirst), findsOneWidget);
    });

    testWidgets('tapping it explains rather than doing nothing', (
      tester,
    ) async {
      await pump(tester);
      await toggle(tester, t.settings.biometricUnlock);

      expect(find.text(t.settings.enablePinFirst), findsWidgets);
      expect(switchFor(tester, t.settings.biometricUnlock).value, isFalse);
    });

    testWidgets('stays off when the device has no biometrics to offer', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({kLockEnabledPrefsKey: true});
      SharedPreferences.resetStatic();
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.biometricUnlock));

      expect(find.text(t.settings.biometricUnavailable), findsOneWidget);
      expect(switchFor(tester, t.settings.biometricUnlock).value, isFalse);
    });
  });

  group('the PIN switch', () {
    testWidgets('reflects a lock that is already on', (tester) async {
      SharedPreferences.setMockInitialValues({kLockEnabledPrefsKey: true});
      SharedPreferences.resetStatic();
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.pinLock));

      expect(switchFor(tester, t.settings.pinLock).value, isTrue);
      expect(find.text(t.settings.pinLockEnabled), findsOneWidget);
    });

    testWidgets('is off on a fresh install', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.pinLock));

      expect(switchFor(tester, t.settings.pinLock).value, isFalse);
      expect(find.text(t.settings.pinLockDisabled), findsOneWidget);
    });

    testWidgets('turning it on asks for a PIN instead of just flipping', (
      tester,
    ) async {
      await pump(tester);
      await toggle(tester, t.settings.pinLock);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(await LockService.instance.isLockEnabled, isFalse);
    });

    testWidgets('a five-digit PIN is set with the tick and confirmed', (
      tester,
    ) async {
      await pump(tester);
      await toggle(tester, t.settings.pinLock);
      Future<void> type(String digits) async {
        for (final d in digits.split('')) {
          await tester.tap(
            find.descendant(of: find.byType(Dialog), matching: find.text(d)),
          );
          await tester.pump();
        }
      }

      await type('1234');
      expect(find.text(t.lock.setPin), findsOneWidget);
      await type('5');
      await tester.tap(find.byTooltip(t.lock.pinNext));
      await tester.pump();
      expect(find.text(t.lock.confirmPin), findsOneWidget);

      await type('12345');
      for (
        var i = 0;
        i < 20 && !await LockService.instance.isLockEnabled;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      expect(await LockService.instance.isLockEnabled, isTrue);
      expect(await LockService.instance.pinLength, 5);
      expect(
        await tester.runAsync(() => LockService.instance.verifyPin('12345')),
        isTrue,
      );
    });
  });

  group('analytics consent', () {
    testWidgets('is off until it is answered', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.analyticsToggle));
      expect(switchFor(tester, t.settings.analyticsToggle).value, isFalse);
    });

    testWidgets('the toggle is the same answer the prompt takes', (
      tester,
    ) async {
      await pump(tester);
      await toggle(tester, t.settings.analyticsToggle);

      expect(switchFor(tester, t.settings.analyticsToggle).value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAnalyticsConsentPrefsKey), isTrue);
    });

    testWidgets('and turns it back off again', (tester) async {
      await pump(tester);
      await toggle(tester, t.settings.analyticsToggle);
      await toggle(tester, t.settings.analyticsToggle);

      expect(switchFor(tester, t.settings.analyticsToggle).value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAnalyticsConsentPrefsKey), isFalse);
    });
  });

  group('anonymize', () {
    testWidgets('writes through to the setting it fronts', (tester) async {
      await pump(tester);
      final before = anonymizeSetting.value;

      await toggle(tester, t.settings.anonymize);

      expect(anonymizeSetting.value, !before);
    });
  });

  group('theme', () {
    testWidgets('follows the system by default', (tester) async {
      await pump(tester);
      expect(themeModeSetting.value, AppThemeMode.system);
      expect(find.text(t.settings.appearance.toUpperCase()), findsOneWidget);
    });
  });

  group('the New badge', () {
    Finder badgeBeside(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
      matching: find.text(t.settings.newBadge),
    );

    testWidgets('marks only tabs at the bottom', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.tabsAtBottom));
      expect(badgeBeside(t.settings.tabsAtBottom), findsOneWidget);
      await scrollTo(tester, find.text(t.settings.commandSuggestions));
      expect(badgeBeside(t.settings.commandSuggestions), findsNothing);
    });

    testWidgets('is gone once the app reaches 1.11.0', (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'Termphin',
        packageName: 'termphin',
        version: '1.11.0',
        buildNumber: '30',
        buildSignature: '',
      );
      await pump(tester);
      await scrollTo(tester, find.text(t.settings.tabsAtBottom));
      expect(badgeBeside(t.settings.tabsAtBottom), findsNothing);
    });
  });

  testWidgets('the info beside Autocomplete explains it without toggling', (
    tester,
  ) async {
    WhatsNewService.instance.debugSetHighlights(const [
      ReleaseHighlight(
        id: kAutocompleteExplainerId,
        version: 'Unreleased',
        title: 'Explained here',
        body: 'Body',
      ),
    ]);
    addTearDown(() => WhatsNewService.instance.debugSetHighlights(null));
    await pump(tester);
    final info = find.byKey(const ValueKey('commandSuggestionsInfo'));
    await scrollTo(tester, info);

    await tester.tap(info);
    await tester.pumpAndSettle();

    expect(find.text('Explained here'), findsOneWidget);
    expect(commandSuggestionsSetting.value, isTrue);
  });

  testWidgets('the info beside Fast upload explains it, sitting by its title', (
    tester,
  ) async {
    WhatsNewService.instance.debugSetHighlights(const [
      ReleaseHighlight(
        id: kFastUploadExplainerId,
        version: 'Unreleased',
        title: 'Upload explained',
        body: 'Body',
        announce: false,
      ),
    ]);
    addTearDown(() => WhatsNewService.instance.debugSetHighlights(null));
    await pump(tester);
    final info = find.byKey(const ValueKey('fastUploadInfo'));
    await scrollTo(tester, info);

    final title = tester.getRect(
      find.descendant(
        of: find.ancestor(of: info, matching: find.byType(Row)).first,
        matching: find.text(t.settings.fastUpload),
      ),
    );
    final button = tester.getRect(info);
    expect(button.width, lessThanOrEqualTo(32));
    expect(button.left - title.right, lessThanOrEqualTo(8));

    await tester.tap(info);
    await tester.pumpAndSettle();

    expect(find.text('Upload explained'), findsOneWidget);
  });
}
