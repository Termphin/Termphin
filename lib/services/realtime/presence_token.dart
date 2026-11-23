import '../account/account_service.dart';
import 'live_presence.dart';

/// The signed-in account's Firebase ID token for the presence backend, a
/// fresh one with [force]; null when nobody is signed in or it could not be
/// had. Comes from the account, so a computer signed in through the browser
/// has one too.
Future<PresenceToken?> firebasePresenceToken({bool force = false}) async {
  try {
    final token = await AccountService.instance.idToken(force: force);
    if (token == null) return null;
    return (token: token.token, expires: token.expires);
  } on Object {
    return null;
  }
}
