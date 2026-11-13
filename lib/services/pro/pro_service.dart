import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../utils/platform_info.dart';
import '../account/account_service.dart';
import '../firebase/firebase_service.dart';

/// RevenueCat's public SDK keys, one per store, given at build time like the
/// Firebase config. A build without them sells nothing.
const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
const _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

/// The entitlement Pro is in RevenueCat; the functions use the same name.
const kProEntitlement = 'pro';

/// One way to buy Pro, as the store prices it.
class ProOffer {
  const ProOffer({
    required this.package,
    required this.price,
    required this.period,
  });

  final Package package;
  final String price;

  /// `monthly`, `annual` or `lifetime`, from the package type.
  final String period;
}

enum ProFailure { cancelled, notSignedIn, unavailable, failed }

class ProException implements Exception {
  const ProException(this.failure);

  final ProFailure failure;
}

/// Buying Pro, through RevenueCat.
///
/// A purchase is tied to the Firebase account: RevenueCat is logged in with
/// the uid, so its webhook can grant the account Pro, which is what the
/// security rules and the relay check. What this service knows about Pro is
/// for the screen only - it never unlocks anything by itself, which a GPL
/// client could not keep from being patched out anyway.
class ProService {
  ProService._();

  static final instance = ProService._();

  /// Whether the signed-in account has Pro, as last heard.
  final active = ValueNotifier<bool>(false);

  bool _configured = false;
  String? _loggedIn;

  String get _key => isIOSPlatform ? _iosKey : _androidKey;

  /// Whether this build can sell Pro at all.
  bool get available => (isAndroidPlatform || isIOSPlatform) && _key.isNotEmpty;

  Future<bool> _ready() async {
    final uid = AccountService.instance.user?.uid;
    if (!available || uid == null) return false;
    if (!_configured) {
      await Purchases.configure(PurchasesConfiguration(_key)..appUserID = uid);
      _configured = true;
      _loggedIn = uid;
    } else if (_loggedIn != uid) {
      await Purchases.logIn(uid);
      _loggedIn = uid;
    }
    return true;
  }

  /// Reads the account's Pro state, from RevenueCat and from the account's
  /// own claim, whichever says yes.
  Future<bool> refresh() async {
    var pro = false;
    try {
      if (await _ready()) {
        final info = await Purchases.getCustomerInfo();
        pro = info.entitlements.active.containsKey(kProEntitlement);
      }
    } catch (_) {}
    pro = pro || await _claim();
    active.value = pro;
    return pro;
  }

  /// The `pro` claim the webhook put on the account, fetched fresh.
  Future<bool> _claim() async {
    if (!FirebaseService.instance.ready) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final token = await user.getIdTokenResult(true);
      return token.claims?['pro'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<ProOffer>> offers() async {
    if (!await _ready()) return const [];
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) return const [];
    return [
      for (final package in current.availablePackages)
        ProOffer(
          package: package,
          price: package.storeProduct.priceString,
          period: switch (package.packageType) {
            PackageType.annual => 'annual',
            PackageType.lifetime => 'lifetime',
            _ => 'monthly',
          },
        ),
    ];
  }

  Future<void> buy(ProOffer offer) => _store(() async {
    if (!await _ready()) throw const ProException(ProFailure.notSignedIn);
    await Purchases.purchase(PurchaseParams.package(offer.package));
  });

  Future<void> restore() => _store(() async {
    if (!await _ready()) throw const ProException(ProFailure.notSignedIn);
    await Purchases.restorePurchases();
  });

  /// Forgets the account in RevenueCat on sign-out, so the next one's
  /// purchases are not mixed with it.
  Future<void> signedOut() async {
    active.value = false;
    if (!_configured || _loggedIn == null) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
    _loggedIn = null;
  }

  Future<void> _store(Future<void> Function() action) async {
    try {
      await action();
    } on PlatformException catch (error) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      throw ProException(
        code == PurchasesErrorCode.purchaseCancelledError
            ? ProFailure.cancelled
            : ProFailure.failed,
      );
    }
    await refresh();
  }
}
