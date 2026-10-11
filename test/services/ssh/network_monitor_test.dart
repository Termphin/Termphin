import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/ssh/network_monitor.dart';

void main() {
  late StreamController<List<ConnectivityResult>> changes;

  const wifi = [ConnectivityResult.wifi];
  const mobile = [ConnectivityResult.mobile];
  const none = [ConnectivityResult.none];

  List<ConnectivityResult> reading(bool online) => online ? wifi : none;

  setUp(() => changes = StreamController<List<ConnectivityResult>>.broadcast());
  tearDown(() => changes.close());

  Future<NetworkMonitor> monitorStartingAt(bool online) async {
    final monitor = NetworkMonitor(
      changes: changes.stream,
      probe: () async => reading(online),
      initiallyOnline: online,
    );
    await monitor.init();
    return monitor;
  }

  test('assumes a network until told otherwise', () {
    expect(NetworkMonitor(changes: changes.stream).isOnline, isTrue);
  });

  test('reports what the probe found at startup', () async {
    final monitor = await monitorStartingAt(false);
    expect(monitor.isOnline, isFalse);
    await monitor.dispose();
  });

  test('a probe that throws leaves the optimistic default alone', () async {
    final monitor = NetworkMonitor(
      changes: changes.stream,
      probe: () async => throw Exception('no platform here'),
    );

    await monitor.init();

    expect(monitor.isOnline, isTrue);
    await monitor.dispose();
  });

  test('signals the network coming back, once per outage', () async {
    final monitor = await monitorStartingAt(true);
    final regained = <void>[];
    monitor.onRegained.listen(regained.add);

    changes.add(none);
    changes.add(wifi);
    await pumpEventQueue();

    expect(regained, hasLength(1));
    expect(monitor.isOnline, isTrue);
    await monitor.dispose();
  });

  test('a handover between two live interfaces is not a comeback', () async {
    final monitor = await monitorStartingAt(true);
    final regained = <void>[];
    monitor.onRegained.listen(regained.add);

    changes.add(mobile);
    changes.add(wifi);
    await pumpEventQueue();

    expect(regained, isEmpty);
    await monitor.dispose();
  });

  test('signals a handover between two live interfaces', () async {
    final monitor = await monitorStartingAt(true);
    final handovers = <void>[];
    monitor.onHandover.listen(handovers.add);

    changes.add(mobile);
    await pumpEventQueue();

    expect(handovers, hasLength(1));
    await monitor.dispose();
  });

  test('losing one of two interfaces is a handover', () async {
    final monitor = await monitorStartingAt(true);
    changes.add([ConnectivityResult.wifi, ConnectivityResult.mobile]);
    await pumpEventQueue();
    final handovers = <void>[];
    monitor.onHandover.listen(handovers.add);

    changes.add(mobile);
    await pumpEventQueue();

    expect(handovers, hasLength(1));
    await monitor.dispose();
  });

  test('the same interfaces reported again are not a handover', () async {
    final monitor = await monitorStartingAt(true);
    final handovers = <void>[];
    monitor.onHandover.listen(handovers.add);

    changes.add(wifi);
    await pumpEventQueue();

    expect(handovers, isEmpty);
    await monitor.dispose();
  });

  test('an outage and a comeback are not a handover', () async {
    final monitor = await monitorStartingAt(true);
    final handovers = <void>[];
    monitor.onHandover.listen(handovers.add);

    changes.add(none);
    changes.add(mobile);
    await pumpEventQueue();

    expect(handovers, isEmpty);
    await monitor.dispose();
  });

  test('a refresh reports a comeback no event ever announced', () async {
    var online = false;
    final monitor = NetworkMonitor(
      changes: changes.stream,
      probe: () async => reading(online),
      initiallyOnline: false,
    );
    await monitor.init();
    final regained = <void>[];
    monitor.onRegained.listen(regained.add);

    online = true;
    await monitor.refresh();
    await pumpEventQueue();

    expect(monitor.isOnline, isTrue);
    expect(regained, hasLength(1));
    await monitor.dispose();
  });

  test('a refresh that finds nothing new stays quiet', () async {
    final monitor = await monitorStartingAt(true);
    final regained = <void>[];
    monitor.onRegained.listen(regained.add);

    await monitor.refresh();
    await pumpEventQueue();

    expect(regained, isEmpty);
    await monitor.dispose();
  });

  test('refreshing a disposed monitor does not throw', () async {
    final monitor = await monitorStartingAt(false);
    await monitor.dispose();

    await expectLater(monitor.refresh(), completes);
  });

  test('stops reporting once disposed', () async {
    final monitor = await monitorStartingAt(true);
    final regained = <void>[];
    monitor.onRegained.listen(regained.add);
    await monitor.dispose();

    changes.add(none);
    changes.add(wifi);
    await pumpEventQueue();

    expect(regained, isEmpty);
  });
}
