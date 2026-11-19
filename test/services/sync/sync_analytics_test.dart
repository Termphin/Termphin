import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/analytics/analytics_service.dart';
import 'package:termphin/services/sync/sync_coordinator.dart';
import 'package:termphin/services/sync/sync_service.dart';

import '../../support/analytics_recorder.dart';
import '../../support/sync_fakes.dart';

void main() {
  late FakeSyncCloud cloud;
  late SyncService service;

  SyncService device() => SyncService(
    cloud: cloud,
    vault: FakeSyncVault(),
    local: FakeSyncLocal(),
    uid: () => 'u1',
  );

  List<({String name, Map<String, Object> parameters})> sent(String name) =>
      analyticsRecorder.events.where((event) => event.name == name).toList();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AnalyticsService.instance.resetForTest();
    await AnalyticsService.instance.setConsent(true);
    analyticsRecorder.clear();
    cloud = FakeSyncCloud();
    service = device();
  });

  test('setting sync up is sent as new, a second device as joined', () async {
    await service.setUp('correct horse');
    await device().unlock('correct horse');

    expect(
      sent(AnalyticsEvent.syncEnabled.eventName).map(
        (event) => event.parameters[AnalyticsProperty.outcome.propertyName],
      ),
      ['new', 'joined'],
    );
  });

  test('a sync refused for want of Pro is sent with its reason', () async {
    await service.setUp('correct horse');
    analyticsRecorder.clear();
    cloud.refusal = const SyncException(SyncFailure.notPro);

    final coordinator = SyncCoordinator(service: service, reload: () async {});
    addTearDown(coordinator.dispose);
    await coordinator.syncNow();

    expect(sent(AnalyticsEvent.syncFailed.eventName).single.parameters, {
      AnalyticsProperty.reason.propertyName: 'not_pro',
    });
  });

  test('a sync that failed for want of a network is not sent', () async {
    await service.setUp('correct horse');
    analyticsRecorder.clear();
    cloud.refusal = const SyncException(SyncFailure.network);

    final coordinator = SyncCoordinator(service: service, reload: () async {});
    addTearDown(coordinator.dispose);
    await coordinator.syncNow();

    expect(sent(AnalyticsEvent.syncFailed.eventName), isEmpty);
  });

  test('enum values go out in snake case', () {
    expect(analyticsName(SyncFailure.passphraseChanged), 'passphrase_changed');
    expect(analyticsName(SyncFailure.network), 'network');
  });
}
