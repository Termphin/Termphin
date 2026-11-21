import 'dart:async';
import 'dart:io';

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

/// The function that checks a purchase with RevenueCat for the server.
const kConfirmProUrl = String.fromEnvironment(
  'TERMPHIN_CONFIRM_PRO_URL',
  defaultValue:
      'https://europe-central2-termphin-hexeosoft.cloudfunctions.net/confirmPro',
);

/// One way to buy Pro, as the store prices it.
class ProOffer {
  const ProOffer({
    required this.package,
    required this.price,
    required this.period,
    this.amount,
    this.perMonth,
    this.trialDays,
  });

  final Package package;
  final String price;

  /// `monthly`, `annual` or `lifetime`, from the package type.
  final String period;

  /// [price] as a number, in the store's currency.
  final double? amount;

  /// What the plan costs a month, as the store formats it, for a yearly plan.
  final String? perMonth;

  /// How long the free trial this account would get runs, in days; null
  /// when there is none or the store offers it no longer.
  final int? trialDays;
}

/// Whether token [claims] grant Pro at [now]: `pro` set, and `proUntil`
/// (milliseconds) absent - a lifetime purchase - or still ahead.
@visibleForTesting
bool claimSaysPro(Map<String, dynamic>? claims, DateTime now) {
  if (claims?['pro'] != true) return false;
  final until = claims?['proUntil'];
  return until is! num || until > now.millisecondsSinceEpoch;
}

/// The server's claim once a disagreement with the store has been checked
/// with RevenueCat: the check's answer, or - when the check gave none (null)
/// - the claim the token already carried, so an outage is not a downgrade.
@visibleForTesting
bool serverAfterCheck(bool claim, bool? checked) => checked ?? claim;

/// Days in a free trial of [value] [unit]s, or null for a length that is
/// not days or weeks - stores offer trials in those, and a month is not a
/// fixed number of days to promise.
@visibleForTesting
int? trialDaysOf(int value, PeriodUnit unit) => switch (unit) {
  PeriodUnit.day => value,
  PeriodUnit.week => value * 7,
  _ => null,
};

/// The free trial [product] comes with for this account: Play's free phase
/// of the offer the store would pick, or the App Store's introductory offer
/// when it costs nothing.
int? _trialDays(StoreProduct product) {
  final free = product.defaultOption?.freePhase?.billingPeriod;
  if (free != null) return trialDaysOf(free.value, free.unit);
  final intro = product.introductoryPrice;
  if (intro != null && intro.price == 0) {
    return trialDaysOf(intro.periodNumberOfUnits, intro.periodUnit);
  }
  return null;
}

/// The store's own page of the subscriptions on this device's account, or
/// null where there is no store.
@visibleForTesting
String? storeSubscriptionsUrl() {
  if (isIOSPlatform) return 'https://apps.apple.com/account/subscriptions';
  if (isAndroidPlatform) {
    return 'https://play.google.com/store/account/subscriptions';
  }
  return null;
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
/// Whether a subscription bought through [store] keeps billing after the
/// account is deleted. A store subscription does, until it is cancelled in
/// that store; one bought on the web (Stripe, or RevenueCat's own billing)
/// is cancelled by the backend when the account is deleted.
bool storeKeepsBilling(Store store) => switch (store) {
  Store.stripe || Store.rcBilling || Store.paddle => false,
  _ => true,
};

class ProService {
  ProService._();

  static final instance = ProService._();

  /// Whether the signed-in account has Pro, as last heard: the store says
  /// so, or the server does. What the screens show.
  final active = ValueNotifier<bool>(false);

  /// Whether the server knows about it too - the `pro` claim on the
  /// account's token, which is what the cloud checks before it lets sync
  /// or push in. Lags [active] by the moment between a purchase and
  /// [confirmOnServer].
  final confirmed = ValueNotifier<bool>(false);

  /// Whether [active] means anything yet: false until the first [refresh]
  /// has finished, with an answer or without one, and again after sign-out.
  final settled = ValueNotifier<bool>(false);

  /// Whether the account's Pro is a subscription bought on the web, as the
  /// store last told: managed or cancelled in the account on the web, not
  /// in a store, and cancelled by the backend when the account is deleted.
  final boughtOnWeb = ValueNotifier<bool>(false);

  void _readStore(CustomerInfo info) {
    final pro = info.entitlements.active[kProEntitlement];
    boughtOnWeb.value = pro != null && !storeKeepsBilling(pro.store);
  }

  bool _configured = false;
  String? _loggedIn;
  DateTime? _refreshedAt;
  Future<bool?>? _confirming;

  /// How often coming back to the app asks the store again.
  static const _resumeGap = Duration(minutes: 5);

  String get _key => isIOSPlatform ? _iosKey : _androidKey;

  /// Whether this build can sell Pro at all.
  bool get available => (isAndroidPlatform || isIOSPlatform) && _key.isNotEmpty;

  Future<bool> _ready() async {
    final uid = AccountService.instance.user?.uid;
    if (!available || uid == null) return false;
    if (!_configured) {
      await Purchases.configure(PurchasesConfiguration(_key)..appUserID = uid);
      Purchases.addCustomerInfoUpdateListener(_storeChanged);
      _configured = true;
      _loggedIn = uid;
    } else if (_loggedIn != uid) {
      await Purchases.logIn(uid);
      _loggedIn = uid;
    }
    return true;
  }

  /// The store's word on a purchase, renewal or expiry, pushed as it
  /// happens - nothing polls for it.
  void _storeChanged(CustomerInfo info) {
    _readStore(info);
    unawaited(_settle(info.entitlements.active.containsKey(kProEntitlement)));
  }

  /// Reads the account's Pro state from the store and the token it already
  /// has, and brings the server along if the store knows more. Called at
  /// launch, on sign-in and when a purchase completes.
  Future<bool> refresh() async {
    _refreshedAt = DateTime.now();
    bool? store;
    try {
      if (await _ready()) {
        final info = await Purchases.getCustomerInfo();
        _readStore(info);
        store = info.entitlements.active.containsKey(kProEntitlement);
      }
    } catch (_) {}
    try {
      return await _settle(store);
    } finally {
      settled.value = true;
    }
  }

  /// Where Google Play takes a promo code. Play applies the code to Pro on
  /// its own; the app only has to hear about the purchase when it comes back.
  static const playRedeemUrl = 'https://play.google.com/redeem';

  /// Stands in for [redeemCode] in tests, and makes [canRedeemCode] true.
  @visibleForTesting
  static Future<void> Function()? redeemOverride;

  /// Whether this build can take a store's code for Pro: an App Store offer
  /// code on iOS, a Google Play promo code on Android.
  bool get canRedeemCode => redeemOverride != null || available;

  /// Whether a code went off to Google Play to be redeemed, so coming back
  /// asks the store at once instead of waiting out [_resumeGap].
  bool _awaitingCode = false;

  /// Starts redeeming a store's code. On iOS it shows the App Store's own
  /// sheet for an offer code - Apple's sheet, not a field of ours, which App
  /// Review requires - and the purchase arrives through the store listener.
  /// On Android the caller opens [playRedeemUrl] next; this only marks that
  /// the purchase is to be picked up on [resumed].
  Future<void> redeemCode() async {
    final override = redeemOverride;
    if (override != null) return override();
    await _store(() async {
      if (!await _ready()) throw const ProException(ProFailure.notSignedIn);
      if (isIOSPlatform) {
        await Purchases.presentCodeRedemptionSheet();
      } else {
        _awaitingCode = true;
      }
    });
  }

  /// [refresh], unless it ran in the last [_resumeGap]: what coming back to
  /// the app calls, so switching apps does not ask the store every time.
  /// Coming back from redeeming a code in Google Play syncs the store's
  /// purchases first, whatever the gap, so the code's Pro shows at once.
  Future<void> resumed() async {
    if (_awaitingCode) {
      _awaitingCode = false;
      try {
        if (await _ready()) await Purchases.syncPurchasesForResult();
      } catch (_) {}
      await refresh();
      return;
    }
    final last = _refreshedAt;
    if (last != null && DateTime.now().difference(last) < _resumeGap) return;
    await refresh();
  }

  /// Brings the two opinions together: the store's, and the server's as the
  /// token carries it. When they differ - a purchase the server has not
  /// heard of, or a subscription that ended while the token still says Pro -
  /// the server is asked to check with RevenueCat, once. A [store] that did
  /// not answer (null: offline, or a build that sells nothing) leaves the
  /// token's word standing.
  /// The store and the server are compared under the account that was
  /// signed in when this began; an answer that arrives after a sign-out or
  /// a switch of account is dropped rather than applied to the next one.
  Future<bool> _settle(bool? store) async {
    final uid = AccountService.instance.user?.uid;
    var server = await _claim(fresh: false) ?? false;
    if (store != null && store != server) {
      server = serverAfterCheck(server, await _confirmChecked());
    }
    if (AccountService.instance.user?.uid != uid) return active.value;
    confirmed.value = server;
    active.value = (store ?? false) || server;
    return active.value;
  }

  /// Has the server check the purchase with RevenueCat now rather than
  /// wait for its webhook, then picks up the token that says so. False when
  /// the check did not happen or did not answer.
  Future<bool> confirmOnServer() async => (await _confirmChecked()) ?? false;

  /// [confirmOnServer] with the failure kept apart: one request at a time,
  /// callers asking meanwhile share its answer, and null when there was no
  /// answer to act on.
  Future<bool?> _confirmChecked() =>
      _confirming ??= _confirm().whenComplete(() => _confirming = null);

  Future<bool?> _confirm() async {
    if (!FirebaseService.instance.ready) return null;
    final uid = AccountService.instance.user?.uid;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final token = await user.getIdToken();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.postUrl(Uri.parse(kConfirmProUrl));
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
        await response.drain<void>();
        if (response.statusCode != HttpStatus.ok) return null;
      } finally {
        client.close();
      }
      final claim = await _claim(fresh: true);
      if (claim == null || AccountService.instance.user?.uid != uid) {
        return null;
      }
      confirmed.value = claim;
      return claim;
    } catch (_) {
      return null;
    }
  }

  /// The `pro` claim on the account's token, the one already held or with
  /// [fresh] a new one from the server - and only until the `proUntil` it
  /// carries, as the security rules read it. Null when the token could not
  /// be read.
  Future<bool?> _claim({required bool fresh}) async {
    if (!FirebaseService.instance.ready) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final token = await user.getIdTokenResult(fresh);
      return claimSaysPro(token.claims, DateTime.now());
    } catch (_) {
      return null;
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
          amount: package.storeProduct.price,
          perMonth: package.storeProduct.pricePerMonthString,
          trialDays: _trialDays(package.storeProduct),
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

  /// Where the store lets the subscriber change or cancel Pro: the address
  /// it gives, or its own subscriptions page when it gives none.
  Future<String?> managementUrl() async {
    try {
      if (await _ready()) {
        final url = (await Purchases.getCustomerInfo()).managementURL;
        if (url != null) return url;
      }
    } catch (_) {}
    return storeSubscriptionsUrl();
  }

  /// Stands in for the store's answer to [renews] in tests.
  @visibleForTesting
  static Future<bool> Function()? renewsOverride;

  /// Whether the account's Pro is a subscription a store will charge for
  /// again - which deleting the account does not stop, only cancelling it in
  /// that store does. Not a lifetime purchase, nor a subscription already
  /// cancelled, nor one bought on the web (see [storeKeepsBilling]). When the
  /// store cannot be asked, whether Pro is on at all: telling someone to
  /// check is better than letting them be charged.
  Future<bool> renews() async {
    final override = renewsOverride;
    if (override != null) return override();
    try {
      if (!await _ready()) return active.value;
      final info = await Purchases.getCustomerInfo();
      final pro = info.entitlements.active[kProEntitlement];
      return pro != null && pro.willRenew && storeKeepsBilling(pro.store);
    } catch (_) {
      return active.value;
    }
  }

  /// Forgets the account in RevenueCat on sign-out, so the next one's
  /// purchases are not mixed with it.
  Future<void> signedOut() async {
    active.value = false;
    confirmed.value = false;
    boughtOnWeb.value = false;
    settled.value = false;
    _refreshedAt = null;
    _awaitingCode = false;
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
