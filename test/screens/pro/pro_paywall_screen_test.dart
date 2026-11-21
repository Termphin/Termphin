import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/pro_source.dart';
import 'package:termphin/providers/account_provider.dart';
import 'package:termphin/screens/pro/pro_paywall_screen.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/analytics/analytics_service.dart';
import 'package:termphin/services/pro/pro_service.dart';
import 'package:termphin/widgets/pro/feature_demos.dart';

import '../../support/analytics_recorder.dart';
import '../../support/test_app.dart';

class _FakePackage extends Fake implements Package {}

class _SignedIn extends AccountNotifier {
  @override
  AccountUser? build() =>
      const AccountUser(uid: 'user-1', provider: AccountProvider.google);
}

ProviderContainer _signedIn() {
  final container = ProviderContainer(
    overrides: [accountProvider.overrideWith(_SignedIn.new)],
  );
  addTearDown(container.dispose);
  return container;
}

ProOffer _offer(String period, {double? amount, int? trialDays}) => ProOffer(
  package: _FakePackage(),
  price: '',
  period: period,
  amount: amount,
  trialDays: trialDays,
);

void main() {
  group('sortedOffers', () {
    test('yearly first, then monthly, then anything else', () {
      final sorted = sortedOffers([
        _offer('lifetime'),
        _offer('monthly'),
        _offer('annual'),
      ]);

      expect(sorted.map((offer) => offer.period), [
        'annual',
        'monthly',
        'lifetime',
      ]);
    });

    test('an empty list stays empty', () {
      expect(sortedOffers(const []), isEmpty);
    });
  });

  group('savingPercent', () {
    test('what a year saves against twelve months, in whole percent', () {
      expect(
        savingPercent(
          _offer('annual', amount: 90),
          _offer('monthly', amount: 10),
        ),
        25,
      );
    });

    test('a saving under five percent is not worth saying', () {
      expect(
        savingPercent(
          _offer('annual', amount: 117),
          _offer('monthly', amount: 10),
        ),
        isNull,
      );
    });

    test('nothing is said without a monthly plan or usable prices', () {
      expect(savingPercent(_offer('annual', amount: 90), null), isNull);
      expect(
        savingPercent(_offer('annual'), _offer('monthly', amount: 10)),
        isNull,
      );
      expect(
        savingPercent(
          _offer('annual', amount: 90),
          _offer('monthly', amount: 0),
        ),
        isNull,
      );
    });
  });

  testWidgets('signed out, the paywall asks for a sign-in instead of saying '
      'prices failed, and reports why and from where', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AnalyticsService.instance.resetForTest();
    await tester.runAsync(() => AnalyticsService.instance.setConsent(true));
    analyticsRecorder.clear();

    await pumpTestApp(
      tester,
      const ProPaywallScreen(source: ProSource.syncCard, offers: []),
    );
    await tester.pump();

    final t = AppLocale.en.buildSync().account.pro.paywall;
    expect(find.text(t.signInForPrices), findsOneWidget);
    expect(find.text(t.noOffers), findsNothing);

    final failed = analyticsRecorder.events.where(
      (event) => event.name == AnalyticsEvent.paywallOffersFailed.eventName,
    );
    expect(failed.single.parameters, {
      AnalyticsProperty.source.propertyName: 'sync_card',
      AnalyticsProperty.reason.propertyName: 'not_signed_in',
    });
  });

  testWidgets('how it works opens the demo over the paywall, with no way '
      'to a second paywall', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpTestApp(
      tester,
      const ProPaywallScreen(source: ProSource.syncCard, offers: []),
    );
    await tester.pump();

    final link = find.byKey(const ValueKey('paywallHowItWorks-liveStatus'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final demo = tester.widget<FeatureDemo>(find.byType(FeatureDemo));
    expect(demo.kind, FeatureDemoKind.live);
    final t = AppLocale.en.buildSync();
    expect(find.text(t.proFeature.seePro), findsNothing);
    expect(
      find.byKey(const ValueKey('paywallHowItWorks-notifications')),
      findsOneWidget,
    );
  });

  group('trial', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('a plan with a free trial is the one headline', (tester) async {
      await pumpTestApp(
        tester,
        ProPaywallScreen(
          source: ProSource.liveStatus,
          offers: [_offer('annual', trialDays: 7), _offer('monthly')],
        ),
        container: _signedIn(),
      );
      await tester.pump();
      expect(find.text('Try Pro free for\u00a07\u00a0days'), findsOneWidget);
      expect(find.text('More from your servers'), findsNothing);
    });

    testWidgets('without one the headline is the tagline', (tester) async {
      await pumpTestApp(
        tester,
        ProPaywallScreen(
          source: ProSource.liveStatus,
          offers: [_offer('annual'), _offer('monthly')],
        ),
        container: _signedIn(),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('paywallHeadline'))).data,
        'More from your servers',
      );
      expect(find.textContaining('free for'), findsNothing);
    });
  });

  group('footer', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => ProService.redeemOverride = null);

    testWidgets('keeps to restore and the legal links, even where a store '
        'code could be taken', (tester) async {
      ProService.redeemOverride = () async {};

      await pumpTestApp(
        tester,
        ProPaywallScreen(
          source: ProSource.syncCard,
          offers: [_offer('annual')],
        ),
        container: _signedIn(),
      );
      await tester.pump();

      final t = AppLocale.en.buildSync().account.pro;
      expect(find.text(t.restore), findsOneWidget);
      expect(find.text(t.redeem), findsNothing);
      expect(find.text(t.paywall.supporter), findsNothing);
    });
  });
}
