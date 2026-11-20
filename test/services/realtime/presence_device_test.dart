import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/agent_feature.dart';
import 'package:termphin/services/realtime/presence_device.dart';

void main() {
  test('the announcement is the OSC the agent takes out of the input', () {
    final bytes = presenceDeviceAnnouncement(
      installId: 'AbC-_123',
      kind: PresenceDeviceKind.phone,
      name: 'Pixel',
    );
    expect(utf8.decode(bytes), '\x1b]5386;device;AbC-_123;phone;UGl4ZWw\x07');
  });

  test('its description stays inside what the agent accepts', () {
    final bytes = presenceDeviceAnnouncement(
      installId: 'x' * 22,
      kind: PresenceDeviceKind.desktop,
      name: 'ż' * 200,
    );
    final description = utf8
        .decode(bytes)
        .substring('\x1b]5386;device;'.length)
        .replaceAll('\x07', '');
    expect(description.length, lessThanOrEqualTo(200));
    expect(RegExp(r'^[A-Za-z0-9_;-]+$').hasMatch(description), isTrue);
    expect(
      PresenceDevice.parse(description)!.name,
      'ż' * maxPresenceDeviceName,
    );
  });

  test('a description reads back, anything else does not', () {
    expect(
      PresenceDevice.parse('id1;tablet;aVBhZA'),
      const PresenceDevice(
        id: 'id1',
        kind: PresenceDeviceKind.tablet,
        name: 'iPad',
      ),
    );
    for (final bad in [
      '',
      'id1;phone',
      'id1;watch;QQ',
      ';phone;QQ',
      'a;phone;!!',
    ]) {
      expect(PresenceDevice.parse(bad), isNull, reason: bad);
    }
  });

  test('only a 0.20.0 master or newer is told', () {
    expect(
      AgentFeature.missingFor('0.19.3'),
      contains(AgentFeature.deviceInfo),
    );
    expect(
      AgentFeature.missingFor('0.20.0'),
      isNot(contains(AgentFeature.deviceInfo)),
    );
  });
}
