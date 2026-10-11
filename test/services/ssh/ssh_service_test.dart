import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/remote_shell.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/ssh/ssh_service.dart';

import '../../support/fixtures.dart';

/// Enough of [SSHSocket] to satisfy the type - [SshService.connectSocket]
/// never touches these members, it only needs a value to store.
class _FakeSocket implements SSHSocket {
  @override
  Stream<Uint8List> get stream => const Stream.empty();

  @override
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;

  @override
  Future<void> get done => Future.value();

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  void destroy() {}
}

/// Mimics the synchronous throw dartssh2's own [SSHSession.close] raises out
/// of its packet writer once the transport underneath it is already gone.
class _ThrowingSession implements SSHSession {
  @override
  void close() => throw Exception('transport gone');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackedSocket extends _FakeSocket {
  bool destroyed = false;

  @override
  void destroy() => destroyed = true;
}

/// A socket whose graceful close never completes - what a half-closed TCP
/// connection to a peer that went away actually does.
class _HangingSocket extends _FakeSocket {
  bool destroyed = false;

  @override
  Future<void> close() => Completer<void>().future;

  @override
  void destroy() => destroyed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the socket the app connects through', () {
    test(
      'has Nagle off, so a small request does not wait on a delayed ACK',
      () async {
        final server = await ServerSocket.bind('127.0.0.1', 0);
        addTearDown(server.close);
        final accepted = server.first;

        final socket = await connectInteractiveSocket(
          '127.0.0.1',
          server.port,
          timeout: const Duration(seconds: 5),
        );
        addTearDown(socket.destroy);
        final peer = await accepted;
        addTearDown(peer.destroy);

        peer.listen((data) => peer.add(data));
        final echoed = Completer<void>();
        socket.stream.listen((_) {
          if (!echoed.isCompleted) echoed.complete();
        });
        final started = DateTime.now();
        socket.sink.add([1]);
        await socket.flush();
        await echoed.future.timeout(const Duration(seconds: 5));
        expect(
          DateTime.now().difference(started),
          lessThan(const Duration(milliseconds: 30)),
        );
      },
    );
  });

  group('SshService.connectSocket', () {
    test(
      'connects on the first try when there is only one candidate',
      () async {
        final attempts = <String>[];
        Duration? connectionTimeout;
        final service = SshService(
          socketConnector: (host, port, {required timeout}) async {
            attempts.add('$host:$port');
            connectionTimeout = timeout;
            return _FakeSocket();
          },
        );
        final profile = profileFixture(host: 'primary.example.com', port: 22);

        await service.connectSocket(profile);

        expect(attempts, ['primary.example.com:22']);
        expect(connectionTimeout, const Duration(seconds: 30));
        expect(service.connectedHost, 'primary.example.com');
      },
    );

    test(
      'falls through to the next candidate when one is unreachable',
      () async {
        final attempts = <String>[];
        final service = SshService(
          socketConnector: (host, port, {required timeout}) async {
            attempts.add(host);
            if (host == 'primary.example.com') {
              throw const SocketException('connection refused');
            }
            return _FakeSocket();
          },
        );
        final profile = profileFixture(
          host: 'primary.example.com',
          fallbackHosts: ['10.0.0.1', 'fallback.example.com'],
        );

        await service.connectSocket(profile);

        expect(attempts, ['primary.example.com', '10.0.0.1']);
        expect(service.connectedHost, '10.0.0.1');
      },
    );

    test('a timeout on one candidate also falls through to the next', () async {
      final attempts = <String>[];
      final service = SshService(
        socketConnector: (host, port, {required timeout}) async {
          attempts.add(host);
          if (host == 'primary.example.com') {
            throw TimeoutException('timed out');
          }
          return _FakeSocket();
        },
      );
      final profile = profileFixture(
        host: 'primary.example.com',
        fallbackHosts: ['fallback.example.com'],
      );

      await service.connectSocket(profile);

      expect(attempts, ['primary.example.com', 'fallback.example.com']);
      expect(service.connectedHost, 'fallback.example.com');
    });

    test('tries the primary host first even after a fallback worked', () async {
      final attempts = <String>[];
      final service = SshService(
        socketConnector: (host, port, {required timeout}) async {
          attempts.add(host);
          return _FakeSocket();
        },
      );
      final profile = profileFixture(
        host: 'primary.example.com',
        fallbackHosts: ['10.0.0.1'],
        lastGoodHost: '10.0.0.1',
      );

      await service.connectSocket(profile);

      expect(attempts, ['primary.example.com']);
      expect(service.connectedHost, 'primary.example.com');
    });

    test('throws with every failure reason when all candidates fail', () async {
      final service = SshService(
        socketConnector: (host, port, {required timeout}) async {
          throw const SocketException('no route to host');
        },
      );
      final profile = profileFixture(
        host: 'primary.example.com',
        fallbackHosts: ['fallback.example.com'],
      );

      await expectLater(
        () => service.connectSocket(profile),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e.toString().contains('primary.example.com') &&
                e.toString().contains('fallback.example.com'),
          ),
        ),
      );
      expect(service.connectedHost, isNull);
    });

    test(
      'parses a host:port fallback entry and connects to that port',
      () async {
        final seen = <String, int>{};
        final service = SshService(
          socketConnector: (host, port, {required timeout}) async {
            seen[host] = port;
            if (host == 'primary.example.com') {
              throw const SocketException('connection refused');
            }
            return _FakeSocket();
          },
        );
        final profile = profileFixture(
          host: 'primary.example.com',
          port: 22,
          fallbackHosts: ['10.0.0.1:2222'],
        );

        await service.connectSocket(profile);

        expect(seen['10.0.0.1'], 2222);
        expect(service.connectedHost, '10.0.0.1:2222');
      },
    );
  });

  /// Tests for the un-connected guard paths and the health-check lifecycle -
  /// everything in [SshService] that does not need a live SSHClient.
  group('SshService without a connection', () {
    test('startShell throws when not connected', () async {
      final service = SshService(
        socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
      );

      await expectLater(
        () => service.startShell(),
        throwsA(
          predicate(
            (e) => e is Exception && e.toString().contains('Not connected.'),
          ),
        ),
      );
    });

    test('startLocalForward throws when not connected', () async {
      final service = SshService(
        socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
      );

      await expectLater(
        () => service.startLocalForward('rule-1', 2222, 'remote', 22),
        throwsA(
          predicate(
            (e) => e is Exception && e.toString().contains('Not connected.'),
          ),
        ),
      );
    });

    test('startRemoteForward throws when not connected', () async {
      final service = SshService(
        socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
      );

      await expectLater(
        () => service.startRemoteForward('rule-1', 2222, 'local', 22),
        throwsA(
          predicate(
            (e) => e is Exception && e.toString().contains('Not connected.'),
          ),
        ),
      );
    });

    test('detectRemoteShell reports unknown when there is no client', () async {
      final service = SshService(
        socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
      );

      expect(await service.detectRemoteShell(), RemoteShellType.unknown);
    });

    test('write on a session-less service is a no-op, not a crash', () {
      final service = SshService(
        socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
      );

      service.write(Uint8List.fromList([104, 105]));
    });

    test(
      'resizeTerminal on a session-less service is a no-op, not a crash',
      () {
        final service = SshService(
          socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
        );

        service.resizeTerminal(80, 24);
      },
    );

    test('isAlive is false before any connection', () {
      final service = SshService(
        socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
      );

      expect(service.isAlive, isFalse);
      expect(service.connectedHost, isNull);
      expect(service.client, isNull);
      expect(service.session, isNull);
    });

    test('disconnect closes the output stream and clears state', () async {
      final service = SshService(
        socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
      );
      var outputDone = false;
      final sub = service.output.listen(
        (_) {},
        onDone: () => outputDone = true,
      );

      await service.disconnect();

      expect(outputDone, isTrue);
      expect(service.client, isNull);
      expect(service.session, isNull);
      await sub.cancel();
    });

    test('disconnect clears state when closing the session throws', () async {
      final service = SshService(
        socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
      );
      service.session = _ThrowingSession();
      var outputDone = false;
      final sub = service.output.listen(
        (_) {},
        onDone: () => outputDone = true,
      );

      await service.disconnect();

      expect(outputDone, isTrue);
      expect(service.client, isNull);
      expect(service.session, isNull);
      await sub.cancel();
    });

    test('a socket that opens after disconnect is closed, not kept', () async {
      final dial = Completer<SSHSocket>();
      final socket = _TrackedSocket();
      final service = SshService(
        socketConnector: (_, _, {required timeout}) => dial.future,
      );

      final connecting = service.connect(profileFixture());
      await service.disconnect();
      dial.complete(socket);

      await expectLater(connecting, throwsA(isA<SshConnectException>()));
      expect(socket.destroyed, isTrue);
      expect(service.client, isNull);
    });

    test('disconnect gives up on a socket that never closes', () {
      fakeAsync((async) {
        final socket = _HangingSocket();
        final service = SshService(
          socketConnector: (_, _, {required timeout}) async => socket,
        );
        var disconnected = false;
        service.connectSocket(profileFixture()).then((_) {
          service.disconnect().then((_) => disconnected = true);
        });
        async.flushMicrotasks();

        expect(
          disconnected,
          isFalse,
          reason: 'the graceful close still has its window',
        );

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(disconnected, isTrue);
        expect(socket.destroyed, isTrue);
      });
    });
  });

  group('SshService health check', () {
    test('fires onConnectionLost immediately when there is no client', () {
      fakeAsync((async) {
        final service = SshService(
          socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
        );
        var lost = 0;
        service.onConnectionLost = () => lost++;

        service.startHealthCheck();
        async.elapse(const Duration(seconds: 15));

        expect(lost, 1);
        async.elapse(const Duration(seconds: 60));
        expect(lost, 1);
      });
    });

    test('stopHealthCheck cancels the timer before it fires', () {
      fakeAsync((async) {
        final service = SshService(
          socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
        );
        var lost = 0;
        service.onConnectionLost = () => lost++;

        service.startHealthCheck();
        service.stopHealthCheck();
        async.elapse(const Duration(seconds: 120));

        expect(lost, 0);
      });
    });
  });

  group('cipher preference', () {
    test('puts the ciphers this client can push in front of AES-GCM', () {
      final gcmIndex = kSshCipherPreference.indexOf(SSHCipherType.aes256gcm);
      final chachaIndex = kSshCipherPreference.indexOf(
        SSHCipherType.chacha20poly1305,
      );
      final ctrIndex = kSshCipherPreference.indexOf(SSHCipherType.aes256ctr);

      expect(chachaIndex, lessThan(gcmIndex));
      expect(ctrIndex, lessThan(gcmIndex));
      expect(chachaIndex, 0);
    });

    test('still offers GCM, for a server that has nothing else', () {
      expect(kSshCipherPreference, contains(SSHCipherType.aes256gcm));
      expect(kSshCipherPreference, contains(SSHCipherType.aes128gcm));
    });

    test('offers no cipher the library treats as legacy', () {
      expect(kSshCipherPreference, isNot(contains(SSHCipherType.aes256cbc)));
      expect(kSshCipherPreference, isNot(contains(SSHCipherType.aes128cbc)));
    });
  });

  group('SshFailureReason', () {
    test('reads the reason off a classified failure', () {
      const error = SshConnectException(
        SshFailureReason.authFailed,
        'Authentication failed. Check your credentials.',
      );

      expect(SshFailureReason.of(error), SshFailureReason.authFailed);
    });

    test('anything else is unknown rather than a guess at the prose', () {
      expect(
        SshFailureReason.of(Exception('Authentication failed')),
        SshFailureReason.unknown,
      );
    });

    test('the message is what callers already render, with no prefix', () {
      const error = SshConnectException(
        SshFailureReason.timeout,
        'Connection timed out during authentication.',
      );

      expect('$error', 'Connection timed out during authentication.');
    });

    test('every reason has a distinct snake_case name', () {
      final names = SshFailureReason.values.map((r) => r.reasonName).toList();

      expect(names.toSet(), hasLength(names.length));
      for (final name in names) {
        expect(name, matches(RegExp(r'^[a-z][a-z_]*$')), reason: name);
      }
    });

    test(
      'a private key missing from the manager is classified, not unknown',
      () async {
        SharedPreferences.setMockInitialValues({});
        final service = SshService(
          socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
        );

        await expectLater(
          service.connect(
            profileFixture(
              authMethod: AuthMethod.privateKey,
              password: null,
              sshKeyId: 'deleted-key',
            ),
          ),
          throwsA(
            isA<SshConnectException>().having(
              (e) => e.reason,
              'reason',
              SshFailureReason.keyMissing,
            ),
          ),
        );
      },
    );

    test(
      'an unreachable candidate queue reports one reason, not its addresses',
      () async {
        final service = SshService(
          socketConnector: (host, port, {required timeout}) async =>
              throw const SocketException('refused'),
        );

        await expectLater(
          service.connectSocket(
            profileFixture(
              host: 'a.example',
              fallbackHosts: const ['b.example'],
            ),
          ),
          throwsA(
            isA<SshConnectException>().having(
              (e) => e.reason,
              'reason',
              SshFailureReason.hostUnreachable,
            ),
          ),
        );
      },
    );
  });
}
