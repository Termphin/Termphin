import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a server that stops answering after the connect is given up on and '
    'disconnected',
    () async {
      final backend = FakeSshBackend();
      final manager = SshSessionManager.test(
        serviceFactory: backend.createService,
      );
      final never = Completer<void>();

      await expectLater(
        manager.withQuietClient(
          profileFixture(),
          (_) => never.future,
          finishWithin: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(
        backend.latestService.backend.calls.map((c) => c.method),
        contains('disconnect'),
      );
    },
  );
}
