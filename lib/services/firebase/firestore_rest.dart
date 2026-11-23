import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../account/account_service.dart';

/// The Firebase project the app's documents live in.
const kFirestoreProjectId = String.fromEnvironment(
  'FIREBASE_PROJECT_ID',
  defaultValue: 'termphin-hexeosoft',
);

/// One Firestore REST call's answer: its status and decoded JSON body.
typedef FirestoreAnswer = ({int status, Object? body});

/// Sends one request to Firestore's REST API with the account's ID token.
/// Stands in for the network in tests.
typedef FirestoreSend =
    Future<FirestoreAnswer> Function(
      String method,
      Uri url, {
      Object? body,
      required String token,
    });

/// Why a Firestore REST call did not succeed.
enum FirestoreRestFailure { signedOut, denied, network, failed }

class FirestoreRestException implements Exception {
  const FirestoreRestException(this.failure);

  final FirestoreRestFailure failure;

  @override
  String toString() => 'FirestoreRestException(${failure.name})';
}

/// Firestore through its REST API, as the signed-in account: on a computer,
/// where the Firestore plugin does not run. The same documents and the same
/// security rules as on a phone - the account's ID token carries the claims
/// the rules read.
class FirestoreRest {
  FirestoreRest({FirestoreSend? send, Future<String?> Function()? token})
    : _send = send ?? _httpSend,
      _token = token ?? _accountToken;

  final FirestoreSend _send;
  final Future<String?> Function() _token;

  static Future<String?> _accountToken() async =>
      (await AccountService.instance.idToken())?.token;

  /// The documents root, to which paths such as `users/u1/records` are added.
  static const root =
      'https://firestore.googleapis.com/v1/projects/$kFirestoreProjectId/databases/(default)/documents';

  /// A document's full resource name, as writes name it.
  static String name(String path) =>
      'projects/$kFirestoreProjectId/databases/(default)/documents/$path';

  /// Sends [method] to [url], signed as the account. Throws
  /// [FirestoreRestException] when nobody is signed in or the network fails;
  /// any answer the server gives comes back for the caller to read.
  Future<FirestoreAnswer> call(String method, Uri url, {Object? body}) async {
    final String? token;
    try {
      token = await _token();
    } on Object {
      throw const FirestoreRestException(FirestoreRestFailure.network);
    }
    if (token == null) {
      throw const FirestoreRestException(FirestoreRestFailure.signedOut);
    }
    try {
      return await _send(method, url, body: body, token: token);
    } on IOException {
      throw const FirestoreRestException(FirestoreRestFailure.network);
    } on TimeoutException {
      throw const FirestoreRestException(FirestoreRestFailure.network);
    }
  }

  /// Throws for an answer that is not a success: a refusal by the rules as
  /// such, anything else as the call failing.
  static void check(FirestoreAnswer answer) {
    if (answer.status >= 200 && answer.status < 300) return;
    if (answer.status == 401 || answer.status == 403) {
      throw const FirestoreRestException(FirestoreRestFailure.denied);
    }
    throw const FirestoreRestException(FirestoreRestFailure.failed);
  }

  /// Whether a write was refused because its precondition - the document
  /// not existing yet - did not hold.
  static bool failedPrecondition(FirestoreAnswer answer) {
    if (answer.status == 409) return true;
    final body = answer.body;
    final error = body is List && body.isNotEmpty ? body.first : body;
    final status = error is Map && error['error'] is Map
        ? (error['error'] as Map)['status']
        : null;
    return status == 'FAILED_PRECONDITION' || status == 'ALREADY_EXISTS';
  }

  /// The `fields` of a document in a REST answer.
  static Map<String, Object?> fields(Object? document) {
    final fields = document is Map ? document['fields'] : null;
    return fields is Map ? fields.cast<String, Object?>() : const {};
  }

  /// The plain value inside a typed REST field, such as `{stringValue: x}`.
  static Object? value(Object? field) {
    if (field is! Map || field.isEmpty) return null;
    return field.values.first;
  }

  static String? string(Object? field) {
    final value = field is Map ? field['stringValue'] : null;
    return value is String ? value : null;
  }

  static DateTime? timestamp(Object? field) {
    final value = field is Map ? field['timestampValue'] : null;
    return value is String ? DateTime.tryParse(value) : null;
  }

  /// The last segment of a document's resource name: its id.
  static String id(Object? document) =>
      '${document is Map ? document['name'] : ''}'.split('/').last;

  static Future<FirestoreAnswer> _httpSend(
    String method,
    Uri url, {
    Object? body,
    required String token,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(method, url);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await response.transform(utf8.decoder).join();
      Object? decoded;
      try {
        decoded = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
      return (status: response.statusCode, body: decoded);
    } finally {
      client.close();
    }
  }
}
