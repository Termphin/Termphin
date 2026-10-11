import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/terminal/osc_markers.dart';

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  group('OscMarkerTracker', () {
    late List<String> seen;
    late OscMarkerTracker tracker;

    setUp(() {
      seen = [];
      tracker = OscMarkerTracker(seen.add);
    });

    test('reports a BEL-terminated payload', () {
      tracker.consume(bytes('hello\x1b]5382;termphin-cwd;/srv\x07world'));
      expect(seen, ['5382;termphin-cwd;/srv']);
    });

    test('reports an ESC-backslash-terminated payload', () {
      tracker.consume(bytes('\x1b]5379;termphin;run-1;0\x1b\\'));
      expect(seen, ['5379;termphin;run-1;0']);
    });

    test('a payload split across chunks is still one marker', () {
      tracker.consume(bytes('\x1b]5382;term'));
      tracker.consume(bytes('phin-cwd;/tmp\x07'));
      expect(seen, ['5382;termphin-cwd;/tmp']);
    });

    test('ordinary output reports nothing', () {
      tracker.consume(bytes('just some text\nand more\n'));
      expect(seen, isEmpty);
    });

    test('an unterminated payload is abandoned, not buffered forever', () {
      tracker.consume(bytes('\x1b]${'x' * 300}\x07'));
      expect(seen, isEmpty);

      tracker.consume(bytes('\x1b]5382;termphin-cwd;/after\x07'));
      expect(seen, ['5382;termphin-cwd;/after']);
    });

    test('an ESC inside a payload that is not a terminator is kept', () {
      tracker.consume(bytes('\x1b]5382;a\x1bZb\x07'));
      expect(seen, ['5382;a\x1bZb']);
    });
  });

  group('ReplayWaiter', () {
    test('a waiter that was never enabled returns at once', () async {
      await ReplayWaiter(enabled: false).wait();
    });

    test('the end-of-replay marker releases the wait', () async {
      final waiter = ReplayWaiter(enabled: true);
      final pending = waiter.wait();
      waiter.onOsc('5380;termphin-replay-end');
      await pending;
    });

    test('output that goes quiet releases the wait too', () async {
      final waiter = ReplayWaiter(enabled: true);
      waiter.onOutput();
      await waiter.wait();
    });
  });

  group('ReplayWaiter resume', () {
    test('a resume marker releases the wait and says it resumed', () async {
      final waiter = ReplayWaiter(enabled: true);
      final pending = waiter.wait();
      waiter.onOsc('5380;termphin-resume-end');
      await pending;

      expect(waiter.resumed, isTrue);
    });

    test('a replay is not a resume', () async {
      final waiter = ReplayWaiter(enabled: true);
      final pending = waiter.wait();
      waiter.onOsc('5380;termphin-replay-end');
      await pending;

      expect(waiter.resumed, isFalse);
    });
  });

  group('OutputOffsetCounter', () {
    late OutputOffsetCounter counter;
    late OscMarkerTracker tracker;

    setUp(() {
      counter = OutputOffsetCounter();
      tracker = OscMarkerTracker(
        (payload) => counter.onOsc(payload, tracker.position),
      );
    });

    void feed(String value) {
      final data = bytes(value);
      tracker.consume(data);
      counter.onChunk(data.length);
    }

    test('knows nothing before the agent says where it is', () {
      feed('prompt \$ ');

      expect(counter.position, isNull);
    });

    test('counts from the marker, not from the start of the chunk', () {
      feed(
        'replay\x1b]5380;termphin-replay-end\x07'
        '\x1b]5383;termphin-offset;9:100\x07abc',
      );

      expect(counter.position, (epoch: '9', offset: 103));
    });

    test('adds every chunk after the marker', () {
      feed('\x1b]5383;termphin-offset;9:7\x07');
      feed('hello');
      feed(' world');

      expect(counter.position, (epoch: '9', offset: 18));
    });

    test('a marker split across chunks still lands on the right byte', () {
      feed('\x1b]5383;termphin-off');
      feed('set;9:50\x07xy');
      feed('z');

      expect(counter.position, (epoch: '9', offset: 53));
    });

    test('a later marker starts the count over, epoch and all', () {
      feed('\x1b]5383;termphin-offset;9:10\x07abc');
      feed('\x1b]5383;termphin-offset;12:500\x07d');

      expect(counter.position, (epoch: '12', offset: 501));
    });

    test('keeps an epoch too large for an int as it came', () {
      feed('\x1b]5383;termphin-offset;18446744073709551615:1\x07');

      expect(counter.position?.epoch, '18446744073709551615');
    });

    test('ignores other markers and malformed positions', () {
      feed('\x1b]5382;termphin-cwd;/tmp\x07');
      feed('\x1b]5383;termphin-offset;abc\x07');
      feed('\x1b]5383;termphin-offset;100\x07');

      expect(counter.position, isNull);
    });
  });
}
