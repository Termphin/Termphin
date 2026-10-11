import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/ssh/connection_quality.dart';

void main() {
  var now = 0;
  late ConnectionQuality quality;

  setUp(() {
    now = 0;
    quality = ConnectionQuality(clock: () => now);
  });

  void ping(int ms) {
    quality.pingSent();
    now += ms;
    quality.pingAnswered(Duration(milliseconds: ms));
  }

  test('a fast link is good and measured', () {
    ping(40);
    ping(60);

    expect(quality.health, ConnectionHealth.good);
    expect(quality.samples, [40, 60]);
    expect(quality.recentLatency, 60);
  });

  test('a slow link is called slow', () {
    ping(400);

    expect(quality.health, ConnectionHealth.slow);
  });

  test('it stays slow until latency is clearly fine again', () {
    ping(400);
    for (var i = 0; i < 5; i++) {
      ping(250);
    }
    expect(quality.health, ConnectionHealth.slow);

    for (var i = 0; i < 3; i++) {
      ping(50);
    }
    expect(quality.health, ConnectionHealth.good);
  });

  test('one spike is not a slow link', () {
    ping(40);
    ping(40);
    ping(2000);

    expect(quality.health, ConnectionHealth.good);
  });

  test('a reply that sat out a stall does not hold it slow afterwards', () {
    ping(40);
    quality.pingSent();
    now += 8000;
    quality.pingAnswered(const Duration(milliseconds: 8000));
    ping(40);
    ping(40);

    expect(quality.health, ConnectionHealth.good);
  });

  test('an unanswered ping with nothing else heard is unresponsive', () {
    ping(40);
    quality.pingSent();
    now += 6000;
    quality.evaluate();

    expect(quality.health, ConnectionHealth.unresponsive);
    expect(quality.silence, const Duration(milliseconds: 6000));
  });

  test('output from the server counts as the server answering', () {
    ping(40);
    quality.pingSent();
    now += 4000;
    quality.heard();
    now += 2000;
    quality.evaluate();

    expect(quality.health, ConnectionHealth.good);
  });

  test('an idle link with no ping out is not unresponsive', () {
    ping(40);
    now += 60000;
    quality.evaluate();

    expect(quality.health, ConnectionHealth.good);
  });

  test('the answer clears it', () {
    quality.pingSent();
    now += 7000;
    quality.evaluate();
    expect(quality.health, ConnectionHealth.unresponsive);

    quality.pingAnswered(const Duration(milliseconds: 7000));
    ping(40);
    ping(40);

    expect(quality.health, ConnectionHealth.good);
  });

  test('keeps a bounded history', () {
    for (var i = 0; i < ConnectionQuality.maxSamples + 5; i++) {
      ping(10 + i);
    }

    expect(quality.samples, hasLength(ConnectionQuality.maxSamples));
    expect(quality.samples.first, 15);
  });

  test('reset forgets the old transport', () {
    ping(400);
    quality.reset();

    expect(quality.health, ConnectionHealth.good);
    expect(quality.samples, isEmpty);
    expect(quality.recentLatency, isNull);
  });
}
