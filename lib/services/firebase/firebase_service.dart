import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_config.dart';

/// Brings Firebase up once per engine, and only when something needs it.
///
/// Starting it is not free of consequence: the SDKs write installation ids to
/// the device as they come up. So it does not start with the app - the native
/// auto-start is removed from the Android manifest, and iOS has no config
/// file to start from - but from the first [start]: consent to analytics, an
/// account, push. A build without [FirebaseConfig.options] - a fork, a
/// desktop - never starts it, and everything that needs it checks
/// [available] and does without.
///
/// [onStart] callbacks run once it is up, whoever started it: analytics uses
/// that to put its own consent back in force, so starting Firebase for an
/// account never turns on crash reports someone switched off.
class FirebaseService {
  FirebaseService._();

  static final instance = FirebaseService._();

  bool _ready = false;
  Future<bool>? _starting;
  final _onStart = <Future<void> Function()>[];

  /// Whether this build has a Firebase project for this platform at all.
  bool get available => FirebaseConfig.options != null;

  /// Whether Firebase is up in this engine.
  bool get ready => _ready;

  /// Runs [callback] each time Firebase comes up - at most once per engine -
  /// or right away when it already is.
  void onStart(Future<void> Function() callback) {
    _onStart.add(callback);
    if (_ready) unawaited(callback());
  }

  /// Starts Firebase if this build has a project for this platform, and says
  /// whether it is up. A failure leaves the app without it rather than
  /// without the app.
  Future<bool> start() => _starting ??= _start();

  Future<bool> _start() async {
    final options = FirebaseConfig.options;
    if (options == null) return false;
    try {
      await Firebase.initializeApp(options: options);
    } catch (error) {
      debugPrint('Firebase did not start: $error');
      _starting = null;
      return false;
    }
    _ready = true;
    for (final callback in [..._onStart]) {
      try {
        await callback();
      } catch (_) {}
    }
    return true;
  }
}
