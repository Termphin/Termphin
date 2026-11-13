import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/account/account_service.dart';

/// The signed-in user, republished from [AccountService].
class AccountNotifier extends Notifier<AccountUser?> {
  @override
  AccountUser? build() {
    final subscription = AccountService.instance.changes.listen(
      (user) => state = user,
    );
    ref.onDispose(() => unawaited(subscription.cancel()));
    return AccountService.instance.user;
  }
}

final accountProvider = NotifierProvider<AccountNotifier, AccountUser?>(
  AccountNotifier.new,
);
