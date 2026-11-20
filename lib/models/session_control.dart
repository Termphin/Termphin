import '../services/realtime/presence_device.dart';

/// Who holds a session that more than one device is attached to, as its
/// agent master said in its `termphin-control` marker.
///
/// The device holding a session is the one typing into it, and the session
/// runs at that device's size. Another device attached at the same time is
/// a viewer: it shows the session at the holder's size rather than its own,
/// so nothing is wrapped for the wrong width, and it types nothing until it
/// takes control.
class SessionControl {
  const SessionControl({
    required this.holds,
    required this.columns,
    required this.rows,
    this.device,
  });

  /// Whether this device holds the session.
  final bool holds;

  /// The size the session runs at: the holder's.
  final int columns;
  final int rows;

  /// The device holding the session, when it said which it is.
  final PresenceDevice? device;

  static const _prefix = '5384;termphin-control;';

  /// Reads `5384;termphin-control;<you|other>;<cols>;<rows>;<device>`; null
  /// for any other payload.
  static SessionControl? parse(String payload) {
    if (!payload.startsWith(_prefix)) return null;
    final parts = payload.substring(_prefix.length).split(';');
    if (parts.length < 4) return null;
    final holds = switch (parts[0]) {
      'you' => true,
      'other' => false,
      _ => null,
    };
    final columns = int.tryParse(parts[1]);
    final rows = int.tryParse(parts[2]);
    if (holds == null || columns == null || rows == null) return null;
    if (columns < 1 || rows < 1) return null;
    final description = parts.sublist(3).join(';');
    return SessionControl(
      holds: holds,
      columns: columns,
      rows: rows,
      device: description.isEmpty ? null : PresenceDevice.parse(description),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionControl &&
      other.holds == holds &&
      other.columns == columns &&
      other.rows == rows &&
      other.device == device;

  @override
  int get hashCode => Object.hash(holds, columns, rows, device);
}
