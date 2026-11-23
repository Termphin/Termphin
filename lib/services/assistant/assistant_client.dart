import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../realtime/presence_keys.dart' show kPresenceUrl;
import '../realtime/presence_token.dart';
import 'assistant_stream.dart';

/// Which assistant service the build talks to: `prod` unless the build says
/// `--dart-define=ASSISTANT_ENV=dev`, which reaches the development
/// instance - open only to its testers.
const kAssistantEnv = String.fromEnvironment(
  'ASSISTANT_ENV',
  defaultValue: 'prod',
);

/// Where one step of a conversation is sent.
Uri assistantStepUri({
  String env = kAssistantEnv,
  String base = kPresenceUrl,
}) => Uri.parse('$base${env == 'dev' ? '/dev' : ''}/v1/assistant/step');

/// The service refused a step; [code] is its error code, such as
/// `pro_required` or `budget_spent`, or `network` when it could not be
/// reached.
class AssistantRequestError implements Exception {
  const AssistantRequestError(this.code, {this.status});

  final String code;
  final int? status;

  @override
  String toString() => 'AssistantRequestError($code, $status)';
}

/// How much of this week's allowance the account has used, from 0 to 1,
/// and when it starts over.
typedef AssistantUsage = ({double used, DateTime renews});

/// Sends a conversation and streams back the step's events.
abstract class AssistantTransport {
  /// The share of this week's allowance used, as the last step reported
  /// it; null before the first.
  double? get lastUsage;

  /// Asks the service how much of this week's allowance is used; null
  /// when it cannot be told - signed out, no Pro, offline.
  Future<AssistantUsage?> fetchUsage();

  /// The events of the next step after [messages]. Throws
  /// [AssistantRequestError] when the service refuses it.
  Stream<SseEvent> step(
    List<Map<String, dynamic>> messages, {
    bool memory = true,
  });

  /// Drops the step under way, if any.
  void cancel();
}

/// [AssistantTransport] over HTTPS to the assistant service, signed in with
/// the account's Firebase ID token.
class HttpAssistantTransport implements AssistantTransport {
  HttpAssistantTransport({
    Uri? uri,
    Future<String?> Function({bool force})? token,
  }) : _uri = uri ?? assistantStepUri(),
       _token = token ?? _firebaseToken;

  final Uri _uri;
  final Future<String?> Function({bool force}) _token;
  HttpClient? _client;

  @override
  double? lastUsage;

  @override
  Future<AssistantUsage?> fetchUsage() async {
    final token = await _token();
    if (token == null) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(_uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final used = decoded['used'];
      final renews = DateTime.tryParse('${decoded['renews']}');
      if (used is! num || renews == null) return null;
      return (used: used.toDouble().clamp(0.0, 1.0), renews: renews);
    } on Object {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<String?> _firebaseToken({bool force = false}) async =>
      (await firebasePresenceToken(force: force))?.token;

  @override
  Stream<SseEvent> step(
    List<Map<String, dynamic>> messages, {
    bool memory = true,
  }) async* {
    final body = utf8.encode(
      jsonEncode({'messages': messages, 'memory': memory}),
    );
    var response = await _send(body, await _token());
    if (response.statusCode == HttpStatus.unauthorized) {
      await response.drain<void>();
      response = await _send(body, await _token(force: true));
    }
    final usage = double.tryParse(response.headers.value('x-phin-usage') ?? '');
    if (usage != null) lastUsage = usage.clamp(0.0, 1.0);
    if (response.statusCode != HttpStatus.ok) {
      final text = await response.transform(utf8.decoder).join();
      throw AssistantRequestError(
        _errorCode(text),
        status: response.statusCode,
      );
    }
    yield* parseSse(
      response.transform(utf8.decoder).transform(const LineSplitter()),
    );
  }

  Future<HttpClientResponse> _send(List<int> body, String? token) async {
    if (token == null) throw const AssistantRequestError('signed_out');
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(_uri);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.add(body);
      return await request.close();
    } on SocketException {
      throw const AssistantRequestError('network');
    } on HttpException {
      throw const AssistantRequestError('network');
    }
  }

  @override
  void cancel() {
    _client?.close(force: true);
    _client = null;
  }

  static String _errorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      return 'unknown';
    }
    return 'unknown';
  }
}
