import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_service.dart';
import '../analytics/analytics_service.dart';
import '../security/aead.dart';
import '../security/secret_cipher.dart';
import 'settings_sync.dart';
import 'storage_sync_local.dart';
import 'sync_crypto.dart';
import 'sync_engine.dart';

/// Where sync stands on this device for the signed-in user.
enum SyncState {
  /// Nobody is signed in, or the build has no accounts.
  signedOut,

  /// The account has no sync yet: a passphrase has to be chosen.
  notSetUp,

  /// The account syncs, and this device has not been given the passphrase.
  locked,

  /// This device holds the key and can sync.
  ready,
}

/// Why setting up, unlocking or syncing did not happen.
enum SyncFailure {
  wrongPassphrase,
  notPro,
  network,
  alreadySetUp,

  /// Sync was turned off for the whole account, from another device.
  turnedOff,

  /// Sync was turned off and on again with another passphrase elsewhere.
  passphraseChanged,
  unknown,
}

class SyncException implements Exception {
  const SyncException(this.failure);

  final SyncFailure failure;

  @override
  String toString() => 'SyncException(${failure.name})';
}

/// The account's sync settings in the cloud: the salt the passphrase is
/// stretched with, and a check sealed with the resulting key.
class SyncMeta {
  const SyncMeta({
    required this.salt,
    required this.iterations,
    required this.check,
  });

  final Uint8List salt;
  final int iterations;
  final String check;
}

/// The cloud, as the service needs it: one account's meta and records.
abstract interface class SyncCloud {
  Future<SyncMeta?> readMeta(String uid);

  /// Writes [meta] unless the account already has one.
  Future<bool> createMeta(String uid, SyncMeta meta);

  SyncRemote records(String uid);

  /// Deletes the account's synced copy and its sync settings, for every
  /// device at once.
  Future<void> deleteAll(String uid);

  /// Fires when another device changes the account's records, so this one
  /// can pull them while it is open. Changes this device is still writing
  /// do not fire.
  Stream<void> watch(String uid);
}

/// The function that turns sync off for an account and deletes its copy.
const kDeleteSyncDataUrl = String.fromEnvironment(
  'TERMPHIN_DELETE_SYNC_URL',
  defaultValue:
      'https://europe-central2-termphin-hexeosoft.cloudfunctions.net/deleteSyncData',
);

/// Where this device keeps the key once unlocked: the platform keystore.
abstract interface class SyncKeyVault {
  Future<Uint8List?> read(String uid);

  Future<void> write(String uid, Uint8List key);

  Future<void> delete(String uid);
}

/// End-to-end encrypted sync of machines, keys, snippets, groups and pinned
/// host keys between the devices of one account.
///
/// The passphrase never leaves the device. It is stretched into the key on
/// the device, the key is kept in the platform keystore, and the cloud holds
/// only a salt, a check that tells a right passphrase from a wrong one, and
/// records sealed with the key. Forgetting the passphrase loses the cloud
/// copy; the devices keep theirs.
class SyncService {
  SyncService({
    SyncCloud? cloud,
    SyncKeyVault? vault,
    SyncLocal? local,
    String? Function()? uid,
  }) : _cloud = cloud ?? FirestoreSyncCloud(),
       _vault = vault ?? KeystoreSyncKeyVault(),
       _local = local ?? StorageSyncLocal(),
       _uid = uid ?? (() => AccountService.instance.user?.uid);

  static SyncService get instance => instanceOverride ?? _default;
  static final _default = SyncService();

  /// Stands in for the real service in tests.
  @visibleForTesting
  static SyncService? instanceOverride;

  final SyncCloud _cloud;
  final SyncKeyVault _vault;
  final SyncLocal _local;
  final String? Function() _uid;

  /// When this device last synced, if it has.
  final lastSynced = ValueNotifier<DateTime?>(null);

  /// The account being synced, if anyone is signed in.
  String? get uid => _uid();

  /// Fires when another device changes [uid]'s records.
  Stream<void> watchRemote(String uid) => _cloud.watch(uid);

  Future<SyncState> state() async {
    final uid = _uid();
    if (uid == null) return SyncState.signedOut;
    if (await _vault.read(uid) != null) return SyncState.ready;
    final meta = await _guard(() => _cloud.readMeta(uid));
    return meta == null ? SyncState.notSetUp : SyncState.locked;
  }

  /// Turns sync on for the account with [passphrase], and syncs.
  Future<SyncReport> setUp(String passphrase) async {
    final uid = _requireUid();
    final salt = randomBytes(16);
    final key = await SyncKey.derive(passphrase, salt);
    final created = await _guard(
      () => _cloud.createMeta(
        uid,
        SyncMeta(
          salt: salt,
          iterations: kSyncKdfIterations,
          check: key.sealCheck(uid),
        ),
      ),
    );
    if (!created) throw const SyncException(SyncFailure.alreadySetUp);
    await _vault.write(uid, key.bytes);
    _noteEnabled('new');
    return syncNow();
  }

  /// Gives this device the passphrase of an account that already syncs,
  /// and syncs.
  Future<SyncReport> unlock(String passphrase) async {
    final uid = _requireUid();
    final meta = await _guard(() => _cloud.readMeta(uid));
    if (meta == null) throw const SyncException(SyncFailure.unknown);
    final key = await SyncKey.derive(
      passphrase,
      meta.salt,
      iterations: meta.iterations,
    );
    if (!key.opensCheck(uid, meta.check)) {
      throw const SyncException(SyncFailure.wrongPassphrase);
    }
    await _vault.write(uid, key.bytes);
    _noteEnabled('joined');
    return syncNow();
  }

  /// Records sync coming on for this device: [outcome] is `new` for an
  /// account that starts syncing, `joined` for one more device of one that
  /// already does.
  void _noteEnabled(String outcome) => unawaited(
    AnalyticsService.instance.capture(
      AnalyticsEvent.syncEnabled,
      properties: {AnalyticsProperty.outcome: outcome},
    ),
  );

  /// Syncs, after checking the account still syncs under this device's key:
  /// one small read, which is what stops a device that missed sync being
  /// turned off from quietly uploading everything again under a key nobody
  /// has any more.
  Future<SyncReport> syncNow() async {
    final uid = _requireUid();
    final bytes = await _vault.read(uid);
    if (bytes == null) throw const SyncException(SyncFailure.unknown);
    final meta = await _guard(() => _cloud.readMeta(uid));
    if (meta == null || !SyncKey(bytes).opensCheck(uid, meta.check)) {
      await forgetOnThisDevice();
      throw SyncException(
        meta == null ? SyncFailure.turnedOff : SyncFailure.passphraseChanged,
      );
    }
    final report = await _guard(
      () => SyncEngine(
        key: SyncKey(bytes),
        uid: uid,
        remote: _cloud.records(uid),
        local: _local,
        base: PreferencesSyncBase(uid),
      ).run(),
    );
    lastSynced.value = DateTime.now();
    return report;
  }

  /// Turns sync off for the whole account: the synced copy is deleted and
  /// every device forgets its key on its next sync. Data on the devices is
  /// not touched. Works without Pro.
  Future<void> deleteEverywhere() async {
    final uid = _requireUid();
    await _guard(() => _cloud.deleteAll(uid));
    await forgetOnThisDevice();
  }

  /// Stops syncing on this device: forgets the key and what was agreed.
  /// The cloud copy and the other devices are left as they are.
  Future<void> forgetOnThisDevice() async {
    final uid = _uid();
    if (uid == null) return;
    await _vault.delete(uid);
    await PreferencesSyncBase(uid).write(const {});
    await SettingsSync.forgetTimes();
    lastSynced.value = null;
  }

  String _requireUid() {
    final uid = _uid();
    if (uid == null) throw const SyncException(SyncFailure.unknown);
    return uid;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SyncException {
      rethrow;
    } on FirebaseException catch (error) {
      throw SyncException(switch (error.code) {
        'permission-denied' => SyncFailure.notPro,
        'unavailable' || 'deadline-exceeded' => SyncFailure.network,
        _ => SyncFailure.unknown,
      });
    }
  }
}

/// The base of the three-way merge, per account, in shared preferences:
/// only hashes of what was agreed, nothing of the records themselves.
class PreferencesSyncBase implements SyncBaseStore {
  PreferencesSyncBase(this.uid);

  final String uid;

  String get _key => 'sync_base_$uid';

  @override
  Future<Map<String, String>> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> write(Map<String, String> hashes) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(hashes));
  }
}

class KeystoreSyncKeyVault implements SyncKeyVault {
  KeystoreSyncKeyVault([
    this._storage = const FlutterSecureStorage(iOptions: kMasterKeyIOSOptions),
  ]);

  final FlutterSecureStorage _storage;

  String _entry(String uid) => 'sync_key_$uid';

  @override
  Future<Uint8List?> read(String uid) async {
    final raw = await _storage.read(key: _entry(uid));
    return raw == null ? null : base64Decode(raw);
  }

  @override
  Future<void> write(String uid, Uint8List key) =>
      _storage.write(key: _entry(uid), value: base64Encode(key));

  @override
  Future<void> delete(String uid) => _storage.delete(key: _entry(uid));
}

/// `users/{uid}/syncMeta/key` and `users/{uid}/records/*` in Firestore.
class FirestoreSyncCloud implements SyncCloud {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _meta(String uid) =>
      _db.collection('users').doc(uid).collection('syncMeta').doc('key');

  @override
  Future<SyncMeta?> readMeta(String uid) async {
    final snapshot = await _meta(uid).get();
    final data = snapshot.data();
    if (data == null) return null;
    return SyncMeta(
      salt: base64Decode(data['salt'] as String),
      iterations: (data['iterations'] as num).toInt(),
      check: data['check'] as String,
    );
  }

  @override
  Future<bool> createMeta(String uid, SyncMeta meta) =>
      _db.runTransaction((transaction) async {
        final reference = _meta(uid);
        if ((await transaction.get(reference)).exists) return false;
        transaction.set(reference, {
          'salt': base64Encode(meta.salt),
          'iterations': meta.iterations,
          'check': meta.check,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });

  @override
  SyncRemote records(String uid) =>
      _FirestoreRecords(_db.collection('users').doc(uid).collection('records'));

  /// Through the `deleteSyncData` function rather than the database: the
  /// rules let no client delete the sync settings, and the function works
  /// without Pro.
  @override
  Future<void> deleteAll(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) {
      throw const SyncException(SyncFailure.unknown);
    }
    final token = await user.getIdToken();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.parse(kDeleteSyncDataUrl));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok) {
        throw const SyncException(SyncFailure.network);
      }
    } on IOException {
      throw const SyncException(SyncFailure.network);
    } on TimeoutException {
      throw const SyncException(SyncFailure.network);
    } finally {
      client.close();
    }
  }

  /// The first snapshot is what is already there, which the sync that
  /// starts the watch has just read; only later ones are news.
  @override
  Stream<void> watch(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('records')
      .snapshots()
      .skip(1)
      .where(
        (snapshot) =>
            !snapshot.metadata.hasPendingWrites &&
            snapshot.docChanges.isNotEmpty,
      );
}

class _FirestoreRecords implements SyncRemote {
  _FirestoreRecords(this._collection);

  final CollectionReference<Map<String, dynamic>> _collection;

  @override
  Future<Map<String, RemoteEntry>> fetchAll() async {
    final snapshot = await _collection.get();
    return {
      for (final document in snapshot.docs)
        if (document.data()['ciphertext'] is String)
          document.id: RemoteEntry(
            ciphertext: document.data()['ciphertext'] as String,
            deleted: document.data()['deleted'] == true,
          ),
    };
  }

  @override
  Future<void> put(String documentId, RemoteEntry entry) =>
      _collection.doc(documentId).set({
        'ciphertext': entry.ciphertext,
        'deleted': entry.deleted,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
