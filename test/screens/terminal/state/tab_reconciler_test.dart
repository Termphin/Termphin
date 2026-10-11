import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/screens/terminal/state/tab_reconciler.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../../../support/fixtures.dart';
import '../../../support/ssh_fakes.dart';

/// `TabReconciler` must not report a tab as closed just because the manager
/// has not caught up with it yet: a brand-new tab, a reused id reopened right
/// after its old session was dropped, and a session still mid-handshake (or
/// one whose handshake just failed) are all unacknowledged without being
/// gone. Reporting any of them as closed would delete a tab that is still
/// opening, reconnecting, or showing its own retry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SshSessionManager manager;
  late TabReconciler reconciler;
  late FakeSshBackend backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeSshBackend();
    manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    reconciler = TabReconciler(manager);
  });

  tearDown(() => manager.dispose());

  /// A tab held by the manager, the way one looks once its session is up.
  String heldTab(String muxName) {
    final id = manager.adoptRemoteSession(profileFixture(), muxName);
    manager.getSession(id)!.dropped = false;
    return id;
  }

  test('leaves a tab the manager still holds', () {
    final id = heldTab('devbox');
    reconciler.seed();

    expect(reconciler.closedElsewhere([id]), isEmpty);
  });

  test('leaves a tab the manager has never acknowledged', () {
    reconciler.seed();

    expect(reconciler.closedElsewhere(['brand-new-id']), isEmpty);
  });

  test('drops a tab the manager has let go', () async {
    final id = heldTab('devbox');
    reconciler.seed();

    await manager.stopSession(id);

    expect(reconciler.closedElsewhere([id]), {id});
  });

  test('a detached session that is opened again is not dropped', () async {
    final id = heldTab('devbox');
    reconciler.seed();

    await manager.stopSession(id);
    final gone = reconciler.closedElsewhere([id]);
    expect(gone, {id});
    reconciler.forget(gone);

    expect(reconciler.closedElsewhere([id]), isEmpty);
  });

  test('a tab whose first connect failed is not reported as closed', () async {
    const id = 'first-connect';
    reconciler.seed();
    backend.connectGate = Completer<void>();
    backend.connectError = Exception('Network is unreachable');

    final pending = manager.startSession(profileFixture(), sessionId: id);
    await backend.connectCalled.future;

    expect(reconciler.closedElsewhere([id]), isEmpty);

    backend.connectGate!.complete();
    await expectLater(pending, throwsA(anything));

    expect(reconciler.closedElsewhere([id]), isEmpty);
  });
}
