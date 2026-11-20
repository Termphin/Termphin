import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The WebSocket subprotocol the presence backend speaks.
const presenceSubprotocol = 'termphin.v1';

/// One open connection to the presence backend.
abstract interface class PresenceSocket {
  /// Text messages from the server; done when the connection closes.
  Stream<String> get messages;

  void send(String message);

  Future<void> close([int code]);

  /// The code the connection closed with, once it has.
  int? get closeCode;
}

/// The server refused the connection before the upgrade, with [status]:
/// 401 for a bad token, 402 for an account without Pro, 429 and 503 for
/// later.
class PresenceRefused implements Exception {
  const PresenceRefused(this.status);

  final int status;

  @override
  String toString() => 'PresenceRefused($status)';
}

/// Opens a connection to [url] with [token] as the bearer credential.
typedef PresenceConnect =
    Future<PresenceSocket> Function(Uri url, String token);

const _websocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/// The HTTP URL the upgrade request goes to: `wss` becomes `https` and `ws`
/// becomes `http`, keeping the port; an `http` or `https` URL stays as it
/// is. Getting this wrong sends the upgrade to the plain-HTTP port, where the
/// proxy only answers with a redirect.
Uri presenceHttpUrl(Uri url) => switch (url.scheme) {
  'wss' => url.replace(scheme: 'https', port: url.hasPort ? url.port : 443),
  'ws' => url.replace(scheme: 'http', port: url.hasPort ? url.port : 80),
  _ => url,
};

/// Connects over `dart:io`. The handshake is done by hand rather than with
/// `WebSocket.connect`, which hides the status of a refused upgrade - and
/// the status is what tells a token to refresh apart from an account without
/// Pro, which must not be retried.
Future<PresenceSocket> connectPresenceSocket(Uri url, String token) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = 'Termphin';
  try {
    final nonce = base64Encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final request = await client
        .getUrl(presenceHttpUrl(url))
        .timeout(const Duration(seconds: 10));
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Version', '13')
      ..set('Sec-WebSocket-Key', nonce)
      ..set('Sec-WebSocket-Protocol', presenceSubprotocol)
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.switchingProtocols) {
      await response.drain<void>().catchError((_) {});
      throw PresenceRefused(response.statusCode);
    }
    final accept = response.headers.value('Sec-WebSocket-Accept');
    final expected = base64Encode(
      sha1.convert(utf8.encode('$nonce$_websocketGuid')).bytes,
    );
    if (accept != expected ||
        response.headers.value('Sec-WebSocket-Protocol') !=
            presenceSubprotocol) {
      throw const PresenceRefused(HttpStatus.badGateway);
    }
    // ignore: close_sinks
    final socket = await response.detachSocket();
    return _IoPresenceSocket(
      WebSocket.fromUpgradedSocket(
        socket,
        protocol: presenceSubprotocol,
        serverSide: false,
      ),
    );
  } finally {
    client.close();
  }
}

class _IoPresenceSocket implements PresenceSocket {
  _IoPresenceSocket(this._socket)
    : messages = _socket
          .where((message) => message is String)
          .cast<String>()
          .asBroadcastStream();

  final WebSocket _socket;

  @override
  final Stream<String> messages;

  @override
  void send(String message) => _socket.add(message);

  @override
  Future<void> close([int code = WebSocketStatus.normalClosure]) =>
      _socket.close(code);

  @override
  int? get closeCode => _socket.closeCode;
}
