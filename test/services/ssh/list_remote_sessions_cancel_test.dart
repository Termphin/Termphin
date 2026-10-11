import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/sftp/cancel_token.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a cancelled listing gives up and tears the connection down', () async {
    final backend = FakeSshBackend()..connectGate = Completer<void>();
    final manager = SshSessionManager.test(
      serviceFactory: backend.createService,
    );
    final cancel = CancelToken();

    final listing = manager.listRemoteSessions(
      profileFixture(),
      cancel: cancel,
    );
    await backend.connectCalled.future;

    cancel.cancel();
    await expectLater(listing, throwsA(isA<TransferCancelled>()));

    expect(
      backend.latestService.backend.calls.map((c) => c.method),
      contains('disconnect'),
    );
  });

  test('a token cancelled before the call never dials at all', () async {
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      serviceFactory: backend.createService,
    );
    final cancel = CancelToken()..cancel();

    await expectLater(
      manager.listRemoteSessions(profileFixture(), cancel: cancel),
      throwsA(isA<TransferCancelled>()),
    );

    expect(
      backend.latestService.backend.calls.map((c) => c.method),
      isNot(contains('connect')),
    );
  });
}
