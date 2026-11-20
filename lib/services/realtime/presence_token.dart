import 'package:firebase_auth/firebase_auth.dart';

import '../firebase/firebase_service.dart';
import 'live_presence.dart';

/// The signed-in account's Firebase ID token for the presence backend, a
/// fresh one with [force]; null when Firebase is not running or nobody is
/// signed in.
Future<PresenceToken?> firebasePresenceToken({bool force = false}) async {
  if (!FirebaseService.instance.ready) return null;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  final result = await user.getIdTokenResult(force);
  final token = result.token;
  final expires = result.expirationTime;
  if (token == null || expires == null) return null;
  return (token: token, expires: expires);
}
