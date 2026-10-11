import '../../models/ssh_profile.dart';

/// Deterministic placeholder text for the Anonymize setting - what stands in
/// for a machine's name, host and user while it is on, so nothing identifying
/// a real server is on screen during a screen share, a screenshot or a session
/// in public.
///
/// The same seed (a profile's id) always maps to the same fake value, so a
/// machine still reads consistently across every screen, and nothing on disk
/// is ever touched.
class IdentityAnonymizer {
  const IdentityAnonymizer._();

  static const _names = [
    'atlas',
    'nimbus',
    'harbor',
    'quartz',
    'ember',
    'cobalt',
    'meadow',
    'falcon',
    'lagoon',
    'summit',
    'cinder',
    'ridge',
  ];

  static const _users = ['deploy', 'admin', 'ops', 'svc', 'runner'];

  static int _hash(String seed) {
    var h = 0;
    for (final code in seed.codeUnits) {
      h = (h * 31 + code) & 0x7fffffff;
    }
    return h;
  }

  static String name(String seed) => _names[_hash('n$seed') % _names.length];

  static String username(String seed) =>
      _users[_hash('u$seed') % _users.length];

  static String host(String seed) {
    final h = _hash('h$seed');
    return '10.${(h >> 16) & 0xff}.${(h >> 8) & 0xff}.${h & 0xff}';
  }
}

/// Scrubs [profile]'s host and username out of [lines].
///
/// A connection log line is free text built upstream from the real host and
/// username, so when anonymized those substrings are scrubbed out rather
/// than re-deriving the whole line.
List<String> anonymizeConnectionLog(List<String> lines, SshProfile profile) {
  return lines
      .map(
        (line) => line
            .replaceAll(profile.host, IdentityAnonymizer.host(profile.id))
            .replaceAll(
              profile.username,
              IdentityAnonymizer.username(profile.id),
            ),
      )
      .toList();
}
