import 'dart:convert';
import 'dart:typed_data';

/// What kind of device is attached to a session, for its icon.
enum PresenceDeviceKind {
  phone,
  tablet,
  desktop;

  static PresenceDeviceKind? fromName(String name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// One of the user's devices attached to a session, as the session's agent
/// reports it: the device's install id, its kind and the name it gave.
class PresenceDevice {
  const PresenceDevice({
    required this.id,
    required this.kind,
    required this.name,
  });

  final String id;
  final PresenceDeviceKind kind;
  final String name;

  /// Reads `<id>;<kind>;<base64url name>`, the description this app sends;
  /// null for anything else.
  static PresenceDevice? parse(String description) {
    final parts = description.split(';');
    if (parts.length != 3 || parts[0].isEmpty) return null;
    final kind = PresenceDeviceKind.fromName(parts[1]);
    if (kind == null) return null;
    try {
      final name = utf8.decode(base64Url.decode(base64Url.normalize(parts[2])));
      return PresenceDevice(id: parts[0], kind: kind, name: name);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PresenceDevice &&
      other.id == id &&
      other.kind == kind &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, kind, name);
}

/// Longest device name sent, so the description stays well inside what the
/// agent keeps.
const maxPresenceDeviceName = 40;

/// Which device this is, as an agent master keeps it:
/// `<install id>;<kind>;<base64url name>`, the name cut to
/// [maxPresenceDeviceName]. Passed with `attach --device` to an agent that
/// takes it, and typed inside [presenceDeviceAnnouncement] to one that
/// does not.
String presenceDeviceDescription({
  required String installId,
  required PresenceDeviceKind kind,
  required String name,
}) {
  final trimmed = name.trim();
  final short = trimmed.length > maxPresenceDeviceName
      ? trimmed.substring(0, maxPresenceDeviceName)
      : trimmed;
  final encodedName = base64Url.encode(utf8.encode(short)).replaceAll('=', '');
  return '$installId;${kind.name};$encodedName';
}

/// What this app types to tell an agent master which device it is:
/// `ESC ] 5386 ; device ; <description> BEL`. The master's attach client
/// takes it out of the input, so the shell never sees it.
Uint8List presenceDeviceAnnouncement(String description) =>
    Uint8List.fromList(utf8.encode('\x1b]5386;device;$description\x07'));
