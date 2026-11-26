import 'relay_key_store.dart';

/// What a machine may do with Termphin Pro: send pushes ([notify]) and show
/// its live status ([live]). Both off for a machine never switched on.
class MachineSwitches {
  const MachineSwitches({this.notify = false, this.live = false});

  static const off = MachineSwitches();

  final bool notify;
  final bool live;

  /// Whether the machine needs anything on the server at all.
  bool get any => notify || live;

  MachineSwitches copyWith({bool? notify, bool? live}) =>
      MachineSwitches(notify: notify ?? this.notify, live: live ?? this.live);

  @override
  bool operator ==(Object other) =>
      other is MachineSwitches && other.notify == notify && other.live == live;

  @override
  int get hashCode => Object.hash(notify, live);

  @override
  String toString() => 'MachineSwitches(notify: $notify, live: $live)';
}

/// The switches flipped on this device for a machine and not on its server
/// yet: only those the user touched. One left null keeps whatever the
/// machine has - on its key, or, for a key from before that switch existed,
/// on the server - so flipping one switch never decides the other.
class MachineSwitchChange {
  const MachineSwitchChange({this.notify, this.live});

  final bool? notify;
  final bool? live;

  /// This change with [later] on top of it.
  MachineSwitchChange then(MachineSwitchChange later) => MachineSwitchChange(
    notify: later.notify ?? notify,
    live: later.live ?? live,
  );

  Map<String, Object?> toJson() => {'notify': ?notify, 'live': ?live};

  static MachineSwitchChange? fromJson(Object? json) => json is Map
      ? MachineSwitchChange(
          notify: json['notify'] as bool?,
          live: json['live'] as bool?,
        )
      : null;

  @override
  bool operator ==(Object other) =>
      other is MachineSwitchChange &&
      other.notify == notify &&
      other.live == live;

  @override
  int get hashCode => Object.hash(notify, live);

  @override
  String toString() => 'MachineSwitchChange(notify: $notify, live: $live)';
}

/// What the machine of [profileId] is shown to do: a switch flipped on this
/// device that has not reached the server yet ([pending]) wins, then the
/// switches on the machine's key, which every device of the account reads;
/// a machine with neither is off.
///
/// A key from before a switch existed does not say: it reads the way the
/// backend treats it until a connect settles it - live on, since its reports
/// are taken, and notifications as the machine's own setting from before the
/// bell ([legacyNotify], `SshProfile.serverNotifications`), which decided
/// whether its server was quiet.
MachineSwitches machineSwitchesFor(
  String profileId, {
  required Map<String, MachineSwitchChange> pending,
  required Iterable<RelayServer> keys,
  bool legacyNotify = true,
}) {
  final waiting = pending[profileId];
  final key = keys.where((key) => key.profileId == profileId).firstOrNull;
  return MachineSwitches(
    notify: waiting?.notify ?? key?.notify ?? (key != null && legacyNotify),
    live: waiting?.live ?? key?.live ?? key != null,
  );
}

/// The change flipping [notify] or [live] of a machine shown as [current]
/// asks for: that switch alone.
MachineSwitchChange flipOf(
  MachineSwitches current, {
  bool notify = false,
  bool live = false,
}) => MachineSwitchChange(
  notify: notify ? !current.notify : null,
  live: live ? !current.live : null,
);

/// Whether [given] - the key id this device last gave a machine - is a
/// legacy key from before keys named their machine: still in the account's
/// [keys] with no `profileId`. A [given] absent from [keys] was revoked or
/// switched off on another device, not a legacy key.
bool isLegacyServerKey(String? given, Iterable<RelayServer> keys) =>
    given != null &&
    keys.any((key) => key.keyId == given && key.profileId == null);

/// Whether reports from the machine of [profileId] are shown live: its
/// switch, or - for a key from before the switch existed, which the
/// realtime backend still takes reports for - on, so a machine that had
/// live status before the switch keeps it.
bool showsLive(
  String profileId, {
  required Map<String, MachineSwitchChange> pending,
  required Iterable<RelayServer> keys,
}) => machineSwitchesFor(profileId, pending: pending, keys: keys).live;

/// What a machine set up now should do, switch by switch: what was flipped
/// on this device ([change]), else what its key says ([key]), else - for a
/// key from before that switch existed - what its server shows it had, asked
/// only then ([hadNotifications], [hadLiveStatus]); a machine without a key
/// starts with both off. Throws when the server cannot be asked: a guess
/// would switch something off, or on, for good.
Future<MachineSwitches> resolveMachineSwitches({
  required MachineSwitchChange? change,
  required RelayServer? key,
  required bool legacyKey,
  required Future<bool> Function() hadNotifications,
  required Future<bool> Function() hadLiveStatus,
}) async {
  final known = key != null || legacyKey;
  return MachineSwitches(
    notify:
        change?.notify ??
        key?.notify ??
        (known ? await hadNotifications() : false),
    live: change?.live ?? key?.live ?? (known ? await hadLiveStatus() : false),
  );
}
