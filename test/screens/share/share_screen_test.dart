import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/screens/search/global_search_screen.dart';
import 'package:termphin/screens/share/share_screen.dart';
import 'package:termphin/screens/share/share_upload_screen.dart';
import 'package:termphin/services/platform/share_intent_service.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/sftp/sftp_service.dart';
import 'package:termphin/services/sftp/upload_plan.dart';
import 'package:termphin/services/ssh/ssh_service.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/sftp_fakes.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();
  final pi = profileFixture(id: 'pi', name: 'raspberry');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  LocalUpload text(String name, String body) => LocalUpload(
    name: name,
    open: () => Stream.value(utf8.encode(body)),
    length: () async => utf8.encode(body).length,
  );

  group('ShareScreen', () {
    Future<List<String>> pumpShare(
      WidgetTester tester,
      SharedContent? content,
    ) async {
      final calls = <String>[];
      final container = ProviderContainer.test(
        overrides: [
          profileStorageProvider.overrideWithValue(FakeProfileStorage([pi])),
        ],
      );
      await pumpTestApp(
        tester,
        ShareScreen(
          take: () async => content,
          finish: () async => calls.add('finish'),
        ),
        container: container,
      );
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('text alone says only files go, and closes on request', (
      tester,
    ) async {
      final calls = await pumpShare(
        tester,
        const SharedContent([], hadText: true),
      );

      expect(find.text(t.share.textOnly), findsOneWidget);
      expect(calls, isEmpty);
      await tester.tap(find.text(t.common.close));
      expect(calls, ['finish']);
    });

    testWidgets('nothing to share closes straight away', (tester) async {
      expect(await pumpShare(tester, null), ['finish']);
    });

    testWidgets('lists machines only, and backing out sends nothing', (
      tester,
    ) async {
      final calls = await pumpShare(
        tester,
        SharedContent([text('notes.txt', 'hi')]),
      );

      expect(find.byType(GlobalSearchScreen), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('raspberry'), findsOneWidget);
      expect(
        find.text(t.globalSearch.openSessions.toUpperCase()),
        findsNothing,
      );

      await tester.tap(find.byTooltip(t.globalSearch.back));
      await tester.pumpAndSettle();
      expect(calls, ['finish']);
      expect(find.byType(ShareUploadScreen), findsNothing);
    });
  });

  group('ShareUploadScreen', () {
    late FakeSshBackend backend;
    late FakeSftpTree tree;

    setUp(() {
      backend = FakeSshBackend();
      tree = FakeSftpTree({
        '/home/user': [sftpDir('docs')],
        '/home/user/docs': [],
      });
    });

    Future<List<bool?>> pumpUpload(
      WidgetTester tester,
      SharedContent content,
    ) async {
      final popped = <bool?>[];
      await pumpTestApp(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped.add(
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => ShareUploadScreen(
                    profile: pi,
                    content: content,
                    newService: backend.createService,
                    openSftp: (client) => SftpService.test(
                      client,
                      () async => FakeSftpClient(tree),
                    ),
                    closeDelay: Duration.zero,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return popped;
    }

    testWidgets('connects without a session, starts at home, uploads and '
        'closes', (tester) async {
      final popped = await pumpUpload(
        tester,
        SharedContent([text('notes.txt', 'hello')]),
      );

      expect(backend.calls.map((c) => c.method), ['connect']);
      expect(find.text('/home/user'), findsOneWidget);
      expect(find.text('docs'), findsOneWidget);
      expect(
        find.text(t.actionDock.uploadNameTo(name: 'notes.txt')),
        findsOneWidget,
      );

      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.actionDock.uploadHere));
      await tester.pumpAndSettle();

      expect(tree.contents['/home/user/docs/notes.txt'], 'hello');
      expect(popped, [true]);
      expect(find.byType(ShareUploadScreen), findsNothing);
    });

    testWidgets('a failed connection says why and can be retried', (
      tester,
    ) async {
      backend.connectError = const SshConnectException(
        SshFailureReason.hostUnreachable,
        'Host unreachable',
      );
      await pumpUpload(tester, SharedContent([text('a.txt', 'x')]));

      expect(find.text(t.share.connectFailed), findsOneWidget);
      expect(find.text(t.connection.errors.hostUnreachable), findsOneWidget);

      backend.connectError = null;
      await tester.tap(find.text(t.common.retry));
      await tester.pumpAndSettle();
      expect(find.text('docs'), findsOneWidget);
    });

    testWidgets('backing out of the folder hangs up and sends nothing', (
      tester,
    ) async {
      final popped = await pumpUpload(
        tester,
        SharedContent([text('a.txt', 'x')]),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(popped, [null]);
      expect(tree.contents, isEmpty);
      expect(backend.latestService.connected, isFalse);
    });
  });
}
