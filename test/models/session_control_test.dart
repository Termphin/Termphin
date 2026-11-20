import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/session_control.dart';
import 'package:termphin/services/realtime/presence_device.dart';

void main() {
  group('SessionControl.parse', () {
    test('reads who holds the session, its size and the holding device', () {
      expect(
        SessionControl.parse(
          '5384;termphin-control;other;200;50;abc;desktop;TWFjQm9vaw',
        ),
        const SessionControl(
          holds: false,
          columns: 200,
          rows: 50,
          device: PresenceDevice(
            id: 'abc',
            kind: PresenceDeviceKind.desktop,
            name: 'MacBook',
          ),
        ),
      );
    });

    test('a holder that never said which device it is has none', () {
      expect(
        SessionControl.parse('5384;termphin-control;you;40;20;'),
        const SessionControl(holds: true, columns: 40, rows: 20),
      );
    });

    test('ignores other markers and anything malformed', () {
      expect(SessionControl.parse('5384;termphin-master;0.19.8'), isNull);
      expect(SessionControl.parse('5384;termphin-control;maybe;1;1;'), isNull);
      expect(SessionControl.parse('5384;termphin-control;you;0;20;'), isNull);
      expect(SessionControl.parse('5384;termphin-control;you;x;20;'), isNull);
      expect(SessionControl.parse('5384;termphin-control;you;40'), isNull);
      expect(
        SessionControl.parse('5384;termphin-control;other;99999;99999;'),
        isNull,
      );
    });
  });
}
