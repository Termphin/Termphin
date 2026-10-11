import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/known_host.dart';
import '../security/secret_cipher.dart';
import 'write_queue.dart';

const kKnownHostsPrefsKey = 'known_hosts_v1';

/// The host keys this device has pinned.
///
/// Sealed rather than stored as plain JSON. A fingerprint is public
/// information, so this is not about secrecy - it is that an attacker who can
/// write into the app's data directory could otherwise replace a pinned
/// fingerprint with their own and turn the check into a rubber stamp. The
/// seal is AEAD over the whole record set, and the key it needs lives in the
/// platform keystore, out of reach of anything short of the keystore itself.
///
/// Losing that key (device transfer, a vendor that drops keystore entries when
/// the screen lock changes) reads as an empty store, which is the same state
/// as a fresh install: every host is asked about again rather than any of them
/// being waved through.
class KnownHostsStore {
  KnownHostsStore({SecretCipher? cipher})
    : _cipher = cipher ?? SecretCipher.instance;

  static final KnownHostsStore instance = KnownHostsStore();

  static const _aad = 'known_hosts';

  final SecretCipher _cipher;
  final WriteQueue _queue = WriteQueue();

  /// Every pinned key, newest first.
  Future<List<KnownHost>> entries() async {
    final hosts = (await _read()).values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return hosts;
  }

  Future<KnownHost?> lookup(String host, int port, String keyType) async =>
      (await _read())[KnownHost.slotFor(host, port, keyType)];

  Future<HostKeyVerdict> check(
    String host,
    int port, {
    required String keyType,
    required String fingerprint,
  }) async {
    final pinned = await lookup(host, port, keyType);
    if (pinned == null) return HostKeyVerdict.unknown;
    return pinned.fingerprint == fingerprint
        ? HostKeyVerdict.trusted
        : HostKeyVerdict.changed;
  }

  /// Pins [entry], replacing whatever was pinned for the same slot. Accepting
  /// a changed key is the same operation as accepting a first one - the
  /// difference is entirely in what the user was asked.
  Future<void> trust(KnownHost entry) => _queue.run(() async {
    final hosts = await _read();
    hosts[entry.slot] = entry;
    await _write(hosts);
  });

  /// Drops every key pinned for an address, whatever its type - what the
  /// known-hosts screen's "forget" does, and the only way back to a clean
  /// first-contact prompt for a host whose key legitimately rotates.
  Future<void> forget(String host, int port) => _queue.run(() async {
    final hosts = await _read();
    hosts.removeWhere((_, entry) => entry.host == host && entry.port == port);
    await _write(hosts);
  });

  Future<void> forgetSlot(String slot) => _queue.run(() async {
    final hosts = await _read();
    hosts.remove(slot);
    await _write(hosts);
  });

  Future<void> clear() => _queue.run(() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(kKnownHostsPrefsKey);
  });

  /// A record set that will not parse cannot be trusted to be complete, and
  /// a partial one is worse than none: it would wave through the entries
  /// that survived and quietly forget the rest, so a decode failure reports
  /// as empty instead.
  Future<Map<String, KnownHost>> _read() async {
    final preferences = await SharedPreferences.getInstance();
    final sealed = preferences.getString(kKnownHostsPrefsKey);
    if (sealed == null) return {};
    final raw = await _cipher.open(sealed, aad: _aad);
    if (raw == null) return {};
    final hosts = <String, KnownHost>{};
    try {
      for (final record in jsonDecode(raw) as List<dynamic>) {
        final entry = KnownHost.fromJson(record as Map<String, dynamic>);
        hosts[entry.slot] = entry;
      }
    } catch (_) {
      return {};
    }
    return hosts;
  }

  Future<void> _write(Map<String, KnownHost> hosts) async {
    final preferences = await SharedPreferences.getInstance();
    final sealed = await _cipher.seal(
      jsonEncode([for (final entry in hosts.values) entry.toJson()]),
      aad: _aad,
    );
    await preferences.setString(kKnownHostsPrefsKey, sealed);
  }
}
