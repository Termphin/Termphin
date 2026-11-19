import '../../i18n/strings.g.dart';
import '../../services/account/account_service.dart';

/// What [failure] means, in the account screens' own words.
String accountFailureText(Translations t, AccountFailure failure) {
  final f = t.account.failure;
  return switch (failure) {
    AccountFailure.invalidEmail => f.invalidEmail,
    AccountFailure.wrongCredentials => f.wrongCredentials,
    AccountFailure.emailInUse => f.emailInUse,
    AccountFailure.weakPassword => f.weakPassword,
    AccountFailure.requiresRecentLogin => f.requiresRecentLogin,
    AccountFailure.network => f.network,
    AccountFailure.tooManyRequests => f.tooManyRequests,
    AccountFailure.unavailable => f.unavailable,
    AccountFailure.cancelled || AccountFailure.unknown => f.unknown,
  };
}
