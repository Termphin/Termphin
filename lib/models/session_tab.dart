import 'dart:math';

/// Remote process that keeps a terminal session alive after SSH disconnects.
enum Multiplexer {
  termphin,
  none;

  static Multiplexer fromName(String? name) => Multiplexer.values.firstWhere(
    (value) => value.name == name,
    orElse: () => Multiplexer.none,
  );

  /// Whether the remote session outlives the SSH transport.
  bool get isPersistent => this != Multiplexer.none;
}

/// A terminal tab the user opened, persisted across app restarts so the
/// multiplexer session on the server can be re-attached later.
///
/// [muxName] is stable for the lifetime of the tab, allowing the Termphin
/// helper session to be resumed.
class SessionTab {
  /// Every session name this app creates starts with this, so the app can
  /// always tell its own sessions apart from ones a user made by hand - kept
  /// on rename too (see [RenamedSessionName]). Bookkeeping only: [displayName]
  /// is what any of this reaches the user as.
  static const ownedPrefix = 'termphin_';

  /// Prefix snippet runs used to be named with. Runs no longer create a
  /// persistent remote session at all, so this only exists to recognise
  /// leftover records written by an older build.
  static const legacySnippetPrefix = 'termphinsnippet_';

  const SessionTab({
    required this.tabId,
    required this.profileId,
    required this.muxName,
    required this.lastSeen,
    this.detached = false,
    this.multiplexer = Multiplexer.termphin,
    this.wasConnected = false,
    this.isRun = false,
  });

  final String tabId;
  final String profileId;
  final String muxName;
  final DateTime lastSeen;

  /// Whether this tab was actually attached (not just open) the last time
  /// the app ran. A cold start has no live transport to check, so this is
  /// what tells a dropped tab from one that was connected right up until
  /// the process died - restoring one and leaving the other alone.
  final bool wasConnected;

  /// True once the user closed the tab without ending the remote session.
  /// Detached tabs stay out of the tab bar but remain resumable.
  final bool detached;
  final Multiplexer multiplexer;

  /// True while this tab is a snippet run rather than a session the user
  /// opened, which is what keeps it out of the tab bar.
  final bool isRun;

  static final _random = Random();

  /// Builds a name accepted by the Termphin helper.
  static String generateMuxName() => '$ownedPrefix${_randomSuffix()}';

  /// The session name as the user should see it. [ownedPrefix] is how the app
  /// recognises its own sessions on a server, not part of what anything is
  /// called, so it never belongs on screen.
  static String displayName(String muxName) => muxName.startsWith(ownedPrefix)
      ? muxName.substring(ownedPrefix.length)
      : muxName;

  static String _randomSuffix() =>
      List.generate(6, (_) => _random.nextInt(16).toRadixString(16)).join();

  SessionTab copyWith({
    String? muxName,
    DateTime? lastSeen,
    bool? detached,
    Multiplexer? multiplexer,
    bool? wasConnected,
    bool? isRun,
  }) => SessionTab(
    tabId: tabId,
    profileId: profileId,
    muxName: muxName ?? this.muxName,
    lastSeen: lastSeen ?? this.lastSeen,
    detached: detached ?? this.detached,
    multiplexer: multiplexer ?? this.multiplexer,
    wasConnected: wasConnected ?? this.wasConnected,
    isRun: isRun ?? this.isRun,
  );

  /// A session name has to survive being a directory name on the server, so
  /// the helper and this agree on one narrow character set.
  ///
  /// Keep this in sync with the remote helper's name validation.
  static const maxNameLength = 64;

  /// Matches the name as typed, not a trimmed copy, so a padded name can
  /// never pass here and then reach the server with its spaces still on -
  /// which this same check would then refuse on the way back.
  static String? validateName(String name) {
    if (name.trim().isEmpty) return 'nameEmpty';
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) return 'nameInvalid';
    if (name.length > maxNameLength) return 'nameInvalid';
    return null;
  }

  Map<String, dynamic> toJson() => {
    'tabId': tabId,
    'profileId': profileId,
    'muxName': muxName,
    'lastSeen': lastSeen.toIso8601String(),
    'detached': detached,
    'multiplexer': multiplexer.name,
    'wasConnected': wasConnected,
    'isRun': isRun,
  };

  /// Records written when runs still owned a persistent session are
  /// recognised by the name that build gave them, since they predate
  /// [isRun]. Records written before [wasConnected] existed always tried to
  /// reconnect on restore, which is the same as having been connected.
  factory SessionTab.fromJson(Map<String, dynamic> json) => SessionTab(
    tabId: json['tabId'] as String,
    profileId: json['profileId'] as String,
    muxName: json['muxName'] as String,
    lastSeen:
        DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now(),
    detached: json['detached'] as bool? ?? false,
    isRun:
        json['isRun'] as bool? ??
        (json['muxName'] as String).startsWith(legacySnippetPrefix),
    wasConnected: json['wasConnected'] as bool? ?? true,
    multiplexer: Multiplexer.fromName(json['multiplexer'] as String?),
  );
}

/// A persistent session living on the remote host.
class RemoteMuxSession {
  const RemoteMuxSession({
    required this.name,
    required this.windows,
    required this.createdAt,
    required this.attached,
    required this.multiplexer,
  });

  final String name;
  final int windows;
  final DateTime createdAt;
  final bool attached;
  final Multiplexer multiplexer;

  /// True for sessions this app created (`termphin_*`).
  bool get isOwned => name.startsWith(SessionTab.ownedPrefix);

  factory RemoteMuxSession.fromMap(Map<Object?, Object?> map) =>
      RemoteMuxSession(
        name: map['name'] as String? ?? '',
        windows: (map['windows'] as int?) ?? 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          ((map['createdAt'] as int?) ?? 0) * 1000,
        ),
        attached: map['attached'] as bool? ?? false,
        multiplexer: Multiplexer.fromName(map['multiplexer'] as String?),
      );
}
