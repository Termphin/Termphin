import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/realtime/presence_socket.dart';

Future<HttpServer> _serve(
  Future<void> Function(HttpRequest request) handle,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) => unawaited(handle(request)));
  addTearDown(() => server.close(force: true));
  return server;
}

Uri _url(HttpServer server) =>
    Uri.parse('ws://127.0.0.1:${server.port}/v1/app');

void main() {
  test('a real upgrade opens, carries messages and the close code', () async {
    String? authorization;
    final server = await _serve((request) async {
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      final socket = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (protocols) => protocols.contains(presenceSubprotocol)
            ? presenceSubprotocol
            : null,
      );
      socket.add('{"type":"snapshot"}');
      await socket.close(4002, 'pro required');
    });

    final socket = await connectPresenceSocket(_url(server), 'the-token');
    expect(authorization, 'Bearer the-token');
    expect(await socket.messages.toList(), ['{"type":"snapshot"}']);
    expect(socket.closeCode, 4002);
  });

  test('the upgrade goes to the HTTP twin of the URL, port kept', () {
    expect(
      presenceHttpUrl(Uri.parse('wss://rt.termphin.dev/v1/app')).toString(),
      'https://rt.termphin.dev/v1/app',
    );
    expect(
      presenceHttpUrl(Uri.parse('ws://127.0.0.1:8090/v1/app')).toString(),
      'http://127.0.0.1:8090/v1/app',
    );
    expect(
      presenceHttpUrl(Uri.parse('https://rt.termphin.dev/v1/app')).scheme,
      'https',
    );
  });

  test('a refused upgrade reports its status', () async {
    for (final status in [401, 402, 503]) {
      final server = await _serve((request) async {
        request.response.statusCode = status;
        await request.response.close();
      });
      await expectLater(
        connectPresenceSocket(_url(server), 'token'),
        throwsA(
          isA<PresenceRefused>().having((e) => e.status, 'status', status),
        ),
      );
    }
  });

  test('a server that does not speak the subprotocol is refused', () async {
    final server = await _serve((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      await socket.close();
    });
    await expectLater(
      connectPresenceSocket(_url(server), 'token'),
      throwsA(isA<PresenceRefused>()),
    );
  });
}
