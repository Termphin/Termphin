@Tags(['security'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the platform projects promise about the app's data and entry points.
/// Read straight from the files, since none of it is visible to Dart - these
/// are one-line edits that would otherwise only surface in a store review or
/// a security report.
///
/// Only the app's own manifest is read. What plugins merge into it at build
/// time is not covered here; `bundletool dump manifest` on a release build is
/// the place to look at that.
final _manifest = File(
  'android/app/src/main/AndroidManifest.xml',
).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
final _plist = File(
  'ios/Runner/Info.plist',
).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Every `<tag ...>` element's opening, attributes and all.
Iterable<String> _elements(String tag) => RegExp(
  '<$tag\\b[^>]*>',
  dotAll: true,
).allMatches(_manifest).map((m) => m.group(0)!);

String? _attribute(String element, String name) =>
    RegExp('android:$name="([^"]*)"').firstMatch(element)?.group(1);

void main() {
  group('Android', () {
    test('nothing leaves the device in a system backup', () {
      final application = _elements('application').single;
      expect(_attribute(application, 'allowBackup'), 'false');
      expect(_attribute(application, 'fullBackupContent'), 'false');
      expect(
        _attribute(application, 'dataExtractionRules'),
        '@xml/data_extraction_rules',
      );

      final rules = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      for (final section in ['cloud-backup', 'device-transfer']) {
        final body = RegExp(
          '<$section>(.*?)</$section>',
          dotAll: true,
        ).firstMatch(rules)!.group(1)!;
        for (final domain in [
          'root',
          'file',
          'database',
          'sharedpref',
          'external',
        ]) {
          expect(
            body,
            contains('<exclude domain="$domain" />'),
            reason: '$section must exclude $domain',
          );
        }
        expect(body, isNot(contains('<include')));
      }
    });

    test('no cleartext traffic and no debuggable build', () {
      final application = _elements('application').single;
      expect(_attribute(application, 'usesCleartextTraffic'), isNot('true'));
      expect(_attribute(application, 'networkSecurityConfig'), isNull);
      expect(_attribute(application, 'debuggable'), isNull);
    });

    /// An element marked `tools:node="remove"` takes a library's component
    /// out of the merged manifest; it is not one of ours.
    test('only the launcher activity is reachable from other apps', () {
      final exported = [
        for (final tag in ['activity', 'service', 'receiver', 'provider'])
          for (final element in _elements(tag))
            if (_attribute(element, 'exported') != 'false' &&
                !element.contains('tools:node="remove"'))
              _attribute(element, 'name'),
      ];
      expect(exported, ['.MainActivity', '.ShareActivity']);
    });

    test('Firebase does not start with the process', () {
      final provider = _elements('provider').singleWhere(
        (element) =>
            _attribute(element, 'name') ==
            'com.google.firebase.provider.FirebaseInitProvider',
      );
      expect(provider, contains('tools:node="remove"'));
    });

    test('Firebase collects nothing until it is switched on', () {
      String? value(String name) => RegExp(
        'android:name="$name"\\s+android:value="([^"]*)"',
      ).firstMatch(_manifest)?.group(1);
      for (final flag in [
        'firebase_analytics_collection_enabled',
        'google_analytics_adid_collection_enabled',
        'google_analytics_default_allow_ad_personalization_signals',
        'google_analytics_automatic_screen_reporting_enabled',
        'firebase_crashlytics_collection_enabled',
        'firebase_messaging_auto_init_enabled',
      ]) {
        expect(value(flag), 'false', reason: flag);
      }
    });

    test('the share entry accepts shares and nothing else', () {
      final block = RegExp(
        r'<activity\s+android:name="\.ShareActivity".*?</activity>',
        dotAll: true,
      ).firstMatch(_manifest)!.group(0)!;
      final actions = {
        for (final match in RegExp(
          r'<action android:name="([^"]*)"',
        ).allMatches(block))
          match.group(1),
      };
      expect(actions, {
        'android.intent.action.SEND',
        'android.intent.action.SEND_MULTIPLE',
      });
      expect(block, isNot(contains('android:scheme')));
      expect(block, isNot(contains('BROWSABLE')));
    });

    test('the only links it answers are ssh:// and termphin://toolbar', () {
      final filters = [
        for (final filter in RegExp(
          '<intent-filter>(.*?)</intent-filter>',
          dotAll: true,
        ).allMatches(_manifest))
          filter.group(1)!,
      ];
      final schemes = [
        for (final filter in filters)
          for (final data in RegExp(
            r'android:scheme="([^"]*)"',
          ).allMatches(filter))
            data.group(1),
      ];
      expect(schemes, ['ssh', 'termphin']);
      final termphin = filters.singleWhere(
        (filter) => filter.contains('android:scheme="termphin"'),
      );
      expect(termphin, contains('android:host="toolbar"'));
    });

    test('permissions are the reviewed set', () {
      final permissions = {
        for (final element in _elements('uses-permission'))
          if (!element.contains('tools:node="remove"'))
            _attribute(element, 'name'),
      };
      expect(permissions, {
        'android.permission.INTERNET',
        'android.permission.ACCESS_LOCAL_NETWORK',
        'android.permission.USE_BIOMETRIC',
        'android.permission.USE_FINGERPRINT',
        'android.permission.WRITE_EXTERNAL_STORAGE',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.POST_PROMOTED_NOTIFICATIONS',
        'android.permission.WAKE_LOCK',
        'android.permission.ACCESS_WIFI_STATE',
        'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      });
    });

    test('a push the system draws uses the status bar icon', () {
      final icons = {
        for (final element in _elements('meta-data'))
          _attribute(element, 'name'): _attribute(element, 'resource'),
      };
      expect(
        icons['com.google.firebase.messaging.default_notification_icon'],
        '@drawable/ic_stat_termphin',
      );
      expect(
        icons['dev.termphin.notification_icon'],
        '@drawable/ic_stat_termphin',
      );
    });

    test('the advertising ID permissions a library brings are taken out', () {
      for (final name in [
        'com.google.android.gms.permission.AD_ID',
        'android.permission.ACCESS_ADSERVICES_AD_ID',
        'android.permission.ACCESS_ADSERVICES_ATTRIBUTION',
      ]) {
        final element = _elements(
          'uses-permission',
        ).where((element) => _attribute(element, 'name') == name);
        expect(element, hasLength(1), reason: name);
        expect(element.single, contains('tools:node="remove"'), reason: name);
      }
    });
  });

  group('iOS', () {
    test('export compliance is left unanswered', () {
      expect(
        _plist,
        isNot(contains('<key>ITSAppUsesNonExemptEncryption</key>')),
      );
    });

    test('App Transport Security is not switched off', () {
      expect(_plist, isNot(contains('<key>NSAllowsArbitraryLoads</key>')));
      expect(
        _plist,
        isNot(contains('<key>NSAllowsArbitraryLoadsInWebContent</key>')),
      );
    });

    test('the only links it answers are ssh://, termphin:// and Google '
        'sign-in\'s return', () {
      final schemes =
          RegExp(
                r'<key>CFBundleURLSchemes</key>\s*<array>(.*?)</array>',
                dotAll: true,
              )
              .allMatches(_plist)
              .expand(
                (m) => RegExp(
                  r'<string>([^<]*)</string>',
                ).allMatches(m.group(1)!).map((s) => s.group(1)),
              );
      expect(schemes.toList(), [
        'ssh',
        'termphin',
        r'$(GOOGLE_REVERSED_CLIENT_ID)',
      ]);
    });
  });
}
