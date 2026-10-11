@Tags(['security'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/ssh_connection_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/terminal/session_view.dart';
import 'package:termphin/widgets/terminal/terminal_pane.dart';

import '../support/fixtures.dart';
import '../support/platform_mocks.dart';
import '../support/ssh_fakes.dart';
import '../support/test_app.dart';

/// The server is not trusted with the keyboard. Output is text for the
/// screen; it must never turn into input the shell runs, whether through a
/// terminal reply that echoes text the server chose or through a paste that
/// breaks out of the bracket the shell asked for.
const _canary = 'canary!injected';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('terminal replies', () {
    late StreamController<Uint8List> output;
    late List<String> sent;

    setUp(() {
      output = StreamController<Uint8List>();
      sent = [];
    });

    tearDown(() => output.close());

    Future<void> feed(WidgetTester tester, String text) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: TerminalPane(
            outputStream: output.stream,
            onInput: (bytes) => sent.add(utf8.decode(bytes)),
            onResize: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      output.add(_bytes(text));
      await tester.pumpAndSettle();
    }

    testWidgets('never echo text the server chose', (tester) async {
      await feed(
        tester,
        [
          '\x1b]0;$_canary\r\x07',
          '\x1b]1;$_canary\r\x07',
          '\x1b]2;$_canary\r\x07',
          '\x1b[20t',
          '\x1b[21t',
          '\x1bP\$q$_canary\x1b\\',
          '\x1bP\$qm\x1b\\',
          '\x1bP+q${hex(_canary)}\x1b\\',
          '\x1bP$_canary\x1b\\',
          '\x1b]52;c;?\x07',
          '\x1b[c',
          '\x1b[6n',
        ].join(),
      );

      expect(sent, isNotEmpty, reason: 'device attributes must still answer');
      final replies = sent.join();
      expect(replies, isNot(contains(_canary)));
      expect(replies, isNot(contains('\r')));
    });

    testWidgets('every reply is a fixed-format report', (tester) async {
      await feed(
        tester,
        '\x1b[c\x1b[>c\x1b[=c\x1b[5n\x1b[6n\x1b[18t\x1b[?2004\$p\x1b[4\$p',
      );

      for (final reply in sent) {
        expect(
          reply,
          matches(
            RegExp(
              r'^(\x1b[\[P][0-9;?>=!|$]*[A-Za-z~]|\x1bP!\|[0-9A-F]*\x1b\\)+$',
            ),
          ),
        );
      }
    });
  });

  group('a tapped link', () {
    Future<List<String>> tapFirstWord(WidgetTester tester, String line) async {
      final output = StreamController<Uint8List>();
      addTearDown(output.close);
      final opened = <String>[];
      await pumpTestApp(
        tester,
        Scaffold(
          body: TerminalPane(
            outputStream: output.stream,
            onInput: (_) {},
            onResize: (_, _) {},
            onLinkDetected: (url, _) => opened.add(url),
          ),
        ),
      );
      await tester.pumpAndSettle();
      output.add(_bytes('$line\r\n'));
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byType(TerminalPane));
      await tester.tapAt(origin + const Offset(30, 6));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('opens a web address', (tester) async {
      expect(await tapFirstWord(tester, 'https://example.com/x'), [
        'https://example.com/x',
      ]);
    });

    for (final line in [
      'javascript:alert(document.cookie)',
      'file:///data/data/dev.termphin/shared_prefs',
      'intent://scan/#Intent;scheme=zxing;end',
      'tel:+48123456789',
    ]) {
      testWidgets('does nothing for ${line.split(':').first}:', (tester) async {
        expect(await tapFirstWord(tester, line), isEmpty);
      });
    }
  });

  group('a paste', () {
    late FakeSshBackend backend;
    late SshSessionManager manager;
    late ProviderContainer container;
    late SshProfile profile;
    late ClipboardMock clipboard;
    final viewKey = GlobalKey<SessionViewState>();

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferences.resetStatic();
      await loadAppSettings();
      profile = profileFixture();
      backend = FakeSshBackend();
      manager = SshSessionManager.test(
        remoteAgentService: FakeRemoteAgentService(backend),
        serviceFactory: backend.createService,
      );
      await manager.startSession(profile, sessionId: 'session-1');
      container = ProviderContainer.test(
        overrides: [sshSessionManagerProvider.overrideWithValue(manager)],
      );
      clipboard = ClipboardMock()..install();
    });

    tearDown(() {
      clipboard.uninstall();
      manager.dispose();
    });

    String written() => [
      for (final call in backend.calls)
        if (call.method == 'write')
          utf8.decode((call.arguments as Map)['data'] as Uint8List),
    ].join();

    /// Mounts the session, lets the shell say what it supports, and pastes.
    Future<String> paste(
      WidgetTester tester, {
      required String clipboardText,
      required bool shellAsksForBrackets,
    }) async {
      if (shellAsksForBrackets) {
        backend.latestService.emit(utf8.encode('\x1b[?2004h\$ '));
        await tester.pump();
      }
      await pumpTestApp(
        tester,
        Scaffold(
          body: SessionView(
            key: viewKey,
            sessionKey: ('session-1', profile),
            viewMode: SessionViewMode.terminal,
            isActive: true,
            onClose: () {},
          ),
        ),
        container: container,
      );
      await container
          .read(sshConnectionProvider(('session-1', profile)).notifier)
          .connect();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      backend.calls.clear();
      clipboard.text = clipboardText;
      await viewKey.currentState!.handlePaste();
      await tester.pump();
      return written();
    }

    testWidgets('is bracketed when the shell asks, so nothing runs by itself', (
      tester,
    ) async {
      final sent = await paste(
        tester,
        clipboardText: 'echo one\necho two\n',
        shellAsksForBrackets: true,
      );

      expect(sent, '\x1b[200~echo one\necho two\n\x1b[201~');
    });

    testWidgets('cannot close the bracket early from inside', (tester) async {
      final sent = await paste(
        tester,
        clipboardText: 'harmless\x1b[201~rm -rf ~\n',
        shellAsksForBrackets: true,
      );

      expect(sent, startsWith('\x1b[200~'));
      expect(sent, endsWith('\x1b[201~'));
      expect('\x1b[201~'.allMatches(sent), hasLength(1));
      expect(sent, contains('rm -rf ~'));
    });

    testWidgets('goes as typed to a shell that never asked', (tester) async {
      final sent = await paste(
        tester,
        clipboardText: 'echo hello',
        shellAsksForBrackets: false,
      );

      expect(sent, 'echo hello');
    });
  });
}

String hex(String text) =>
    utf8.encode(text).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
