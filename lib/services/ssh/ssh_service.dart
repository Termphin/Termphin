import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../../i18n/strings.g.dart';
import '../../models/known_host.dart';
import '../../models/remote_shell.dart';
import '../../models/ssh_profile.dart';
import '../../utils/platform_info.dart';
import '../storage/known_hosts_store.dart';
import '../storage/profile_storage.dart';
import '../storage/ssh_key_storage.dart';
import 'connection_quality.dart';
import 'keepalive_pinger.dart';
import 'local_network_permission.dart';
import 'ssh_prompts.dart';

/// Cipher preference, ordered by what this client can actually push.
///
/// dartssh2's default leads with AES-GCM, which pointycastle implements in
/// pure Dart at roughly 1 MB/s - about fifty times slower than its own CTR
/// and ChaCha20, and the ceiling every SFTP transfer was hitting. Nothing
/// here is a weaker choice: ChaCha20-Poly1305 is an AEAD in its own right and
/// AES-CTR is paired with encrypt-then-MAC. GCM stays on the list last, for a
/// server that offers nothing else.
const kSshCipherPreference = [
  SSHCipherType.chacha20poly1305,
  SSHCipherType.aes256ctr,
  SSHCipherType.aes128ctr,
  SSHCipherType.aes256gcm,
  SSHCipherType.aes128gcm,
];

/// Everything this client negotiates. Only the lists that differ from
/// dartssh2's are spelled out; `test/security/ssh_algorithms_test.dart` checks
/// the whole set, so an upgrade that changes a default cannot slip in a weak
/// algorithm. dartssh2 still offers hmac-sha1 last; a server with neither an
/// AEAD cipher nor a SHA-2 MAC predates OpenSSH 5.9.
const kSshAlgorithms = SSHAlgorithms(
  cipher: kSshCipherPreference,
  mac: [
    SSHMacType.hmacSha256Etm,
    SSHMacType.hmacSha512Etm,
    SSHMacType.hmacSha256,
    SSHMacType.hmacSha512,
  ],
);

/// Why a connection attempt did not come up, as a closed set.
///
/// The message a failure carries is written for the user and interpolates
/// whatever it has to hand - addresses, a bastion's profile name, a driver's
/// own error text. None of that can be reported anywhere, so the reason is
/// classified where it is thrown rather than pattern-matched out of English
/// prose later.
enum SshFailureReason {
  hostUnreachable('host_unreachable'),
  localNetworkBlocked('local_network_blocked'),

  /// Every address was local and none answered. Unlike [localNetworkBlocked]
  /// this is a guess: iOS exposes no way to read the permission, so a machine
  /// that is simply switched off looks exactly the same.
  localNetworkUnverified('local_network_unverified'),
  timeout('timeout'),
  authFailed('auth_failed'),
  authError('auth_error'),
  hostKeyRejected('host_key_rejected'),
  hostKeyMismatch('host_key_mismatch'),
  keyMissing('key_missing'),
  keyPassphrase('key_passphrase'),
  keyInvalid('key_invalid'),
  jumpHost('jump_host'),
  jumpHostConfig('jump_host_config'),
  protocol('protocol'),
  unknown('unknown');

  const SshFailureReason(this.reasonName);
  final String reasonName;

  /// What a failure that did not come from [SshService] reports as - a
  /// dropped transport, a session the manager could not start.
  static SshFailureReason of(Object error) =>
      error is SshConnectException ? error.reason : unknown;
}

/// A connection failure with its [reason] kept alongside the text.
///
/// [toString] is the bare message, so every caller that already renders
/// `error.toString()` keeps rendering exactly what it did before.
class SshConnectException implements Exception {
  const SshConnectException(this.reason, this.message);

  final SshFailureReason reason;
  final String message;

  @override
  String toString() => message;
}

/// Turns a profile's key selection into the identities it authenticates with.
///
/// Split out of [SshService.connect] because this is where a key goes wrong
/// on its own terms, before any server is asked anything: dartssh2 reports a
/// bad passphrase and an unreadable file as [SSHKeyDecodeError], which is not
/// an [SSHAuthError], so inline they both landed in the catch-all and were
/// reported as a protocol failure with the library's own text on screen.
/// Standing alone it is also testable without a transport. A PEM that is
/// malformed or of a type dartssh2 does not implement never reaches an
/// [SSHError] at all, which is why [FormatException] and [UnsupportedError]
/// get their own clauses alongside it.
Future<List<SSHKeyPair>?> resolveIdentities(
  SshProfile profile, {
  SshKeyStorage? keyStorage,
}) async {
  if (profile.authMethod != AuthMethod.privateKey) return null;

  final String? pem;
  if (profile.sshKeyId != null) {
    final stored = await (keyStorage ?? SshKeyStorage()).getKey(
      profile.sshKeyId!,
    );
    if (stored == null) {
      throw const SshConnectException(
        SshFailureReason.keyMissing,
        'SSH key not found in key manager.',
      );
    }
    pem = stored.privateKeyPem;
  } else {
    pem = profile.privateKey;
  }
  if (pem == null) return null;

  try {
    return SSHKeyPair.fromPem(
      pem,
      profile.passphrase?.isEmpty == true ? null : profile.passphrase,
    );
  } on SSHKeyDecryptError {
    throw const SshConnectException(
      SshFailureReason.keyPassphrase,
      'The key could not be unlocked. Check its passphrase.',
    );
  } on SSHKeyDecodeError {
    throw const SshConnectException(
      SshFailureReason.keyInvalid,
      'The key could not be read.',
    );
  } on FormatException {
    throw const SshConnectException(
      SshFailureReason.keyInvalid,
      'The key could not be read.',
    );
  } on UnsupportedError {
    throw const SshConnectException(
      SshFailureReason.keyInvalid,
      'This key format is not supported.',
    );
  }
}

/// Opens the transport-level socket for one candidate address. Overridable on
/// [SshService] so tests can exercise the fallback-queue logic in [SshService
/// .connect] without opening real sockets.
typedef SocketConnector =
    Future<SSHSocket> Function(
      String host,
      int port, {
      required Duration timeout,
    });

/// Opens the transport to one candidate address, however this connection
/// reaches it - a socket off the device, or a channel forwarded by a bastion.
typedef TransportOpener =
    Future<SSHSocket> Function(SshEndpoint endpoint, Duration timeout);

/// A socket with Nagle's algorithm turned off, which `SSHSocket.connect` does
/// not do. Left on, every small request waits for the peer's delayed ACK
/// before the next one goes out: measured at ~40ms per round trip, which is
/// what a keystroke echo and every single SFTP stat/remove costs. OpenSSH
/// sets TCP_NODELAY on its interactive sessions for the same reason.
Future<SSHSocket> connectInteractiveSocket(
  String host,
  int port, {
  required Duration timeout,
}) async {
  // ignore: close_sinks - ownership of socket is passed to _InteractiveSshSocket
  final socket = await Socket.connect(host, port, timeout: timeout);
  socket.setOption(SocketOption.tcpNoDelay, true);
  return _InteractiveSshSocket(socket);
}

class _InteractiveSshSocket implements SSHSocket {
  _InteractiveSshSocket(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _socket.done;

  @override
  void destroy() => _socket.destroy();

  @override
  Future<void> flush() => _socket.flush();

  @override
  String toString() =>
      '_InteractiveSshSocket(${_socket.remoteAddress.host}:'
      '${_socket.remotePort})';
}

class SshService {
  SshService({
    SocketConnector? socketConnector,
    KnownHostsStore? knownHosts,
    ProfileStorage? profiles,
  }) : _socketConnector = socketConnector ?? connectInteractiveSocket,
       _knownHosts = knownHosts ?? KnownHostsStore.instance,
       _profiles = profiles ?? ProfileStorage();

  final SocketConnector _socketConnector;
  final KnownHostsStore _knownHosts;

  /// Only ever read, and only to resolve a jump host - a profile names its
  /// bastion by id so the bastion's own credentials and host key live in one
  /// place instead of being copied into every profile behind it.
  final ProfileStorage _profiles;

  /// How many bastions a connection may be chained through. High enough for
  /// any real topology, low enough that a profile chain that loops back on
  /// itself reports that instead of connecting forever.
  static const int _maxJumpDepth = 4;

  /// The session carrying this one, when the profile connects through a
  /// bastion. Torn down with this service - a forwarded channel outliving its
  /// carrier is just a leak.
  SshService? _jumpHost;

  SSHSocket? _socket;
  SSHClient? _client;
  SSHSession? _session;
  final StreamController<Uint8List> _outputController =
      StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;
  bool _isDisposed = false;

  static const Duration _connectionTimeout = Duration(seconds: 30);

  /// All a graceful FIN exchange gets before the socket is destroyed - see
  /// [_closeSocket].
  static const Duration _socketCloseTimeout = Duration(seconds: 2);

  final Map<String, ServerSocket> _localListeners = {};
  final Map<String, SSHRemoteForward> _remoteForwards = {};
  final Map<String, StreamSubscription<SSHForwardChannel>> _remoteForwardSubs =
      {};

  Stream<Uint8List> get output => _outputController.stream;

  SSHClient? get client => _client;

  SSHSession? get session => _session;

  /// Exposed for tests the same way [connectSocket] is - reaching a shell
  /// session through a real handshake would mean standing up an SSH server
  /// to test what happens when it fails to close.
  @visibleForTesting
  set session(SSHSession? value) => _session = value;

  bool get isAlive => _client != null && !_client!.isClosed;

  void Function()? onConnectionLost;

  Map<String, ServerSocket> get localListeners => _localListeners;
  Map<String, SSHRemoteForward> get remoteForwards => _remoteForwards;

  /// The address from [SshProfile.connectionCandidates] that this connection
  /// actually reached, once [connect] succeeds. The caller persists it as
  /// [SshProfile.lastGoodHost] so the next attempt tries it right after the
  /// main host, ahead of the other fallbacks.
  String? connectedHost;

  /// [connectedHost] resolved to an address and a port. This, not the
  /// profile's nominal host, is what a host key is pinned against: a profile
  /// with fallbacks reaches several machines' worth of addresses, and each
  /// one answers with its own key.
  SshEndpoint? _connectedEndpoint;

  /// Wall-clock time this connection has spent waiting on the user.
  ///
  /// The auth timeout exists to give up on a server that stopped answering.
  /// A host key dialog or a 2FA prompt is the opposite of that - the exchange
  /// is going fine, it is us who have not replied yet - so the time spent in
  /// one is handed back to the budget in [_awaitAuthenticated].
  Duration _promptedFor = Duration.zero;

  /// Tries [SshProfile.connectionCandidates] in order and sets [_socket] and
  /// [connectedHost] to the first one that answers. Split out from [connect]
  /// so the fallback-queue behavior is unit-testable without going through a
  /// real SSH handshake.
  ///
  /// From Android 17 a socket to a LAN address without `ACCESS_LOCAL_NETWORK`
  /// is dropped as a timeout rather than refused, so dialling one already
  /// known to be blocked only buys 30 seconds of waiting for an answer that
  /// cannot come; asking for the permission is the UI's job, this only says
  /// which failure it was. Skipped behind a jump host, whose traffic leaves as
  /// a channel on the bastion's session - nothing local left here. Only the
  /// last candidate gets the full timeout, so a queue of fallbacks fails fast
  /// enough to still reach a working one within a reasonable total wait. A
  /// channel the bastion could not open means the same as a refused socket
  /// and falls through to the next candidate the same way. iOS gates the LAN
  /// the same way but tells nobody, so the only place the guess can be made is
  /// after every address has timed out.
  @visibleForTesting
  Future<void> connectSocket(
    SshProfile profile, {
    void Function(String message)? onConnectionLog,
    HostKeyPrompt? onHostKeyPrompt,
    KeyboardInteractivePrompt? onKeyboardInteractive,
    int jumpDepth = 0,
  }) async {
    final open = await _transportOpener(
      profile,
      onConnectionLog: onConnectionLog,
      onHostKeyPrompt: onHostKeyPrompt,
      onKeyboardInteractive: onKeyboardInteractive,
      jumpDepth: jumpDepth,
    );

    final candidates = profile.connectionCandidates;
    final endpoints = [
      for (final candidate in candidates)
        SshEndpoint.parse(candidate, defaultPort: profile.port),
    ];

    if (profile.jumpHostProfileId == null &&
        await _blockedByLocalNetwork(endpoints)) {
      await _closeJumpHost();
      throw SshConnectException(
        SshFailureReason.localNetworkBlocked,
        'Local network access is not allowed. Termphin needs permission to '
        'reach ${endpoints.map((e) => e.host).join(', ')}.',
      );
    }

    final failures = <String>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final endpoint = endpoints[i];
      final isLast = i == candidates.length - 1;
      if (candidates.length > 1) {
        onConnectionLog?.call(
          t.connectionLog.trying(host: endpoint.host, port: endpoint.port),
        );
      }
      try {
        final socket = await open(
          endpoint,
          isLast ? _connectionTimeout : const Duration(seconds: 4),
        );
        if (_isDisposed) {
          socket.destroy();
          await _closeJumpHost();
          throw _abandoned;
        }
        _socket = socket;
        connectedHost = candidate;
        _connectedEndpoint = endpoint;
        return;
      } on SocketException catch (error) {
        failures.add('${endpoint.host}: ${error.message}');
      } on TimeoutException {
        failures.add('${endpoint.host}: timed out');
      } on SSHChannelOpenError catch (error) {
        failures.add('${endpoint.host}: ${error.description}');
      }
    }
    await _closeJumpHost();
    if (isIOSPlatform &&
        profile.jumpHostProfileId == null &&
        await allOnLocalNetwork(endpoints.map((e) => e.host))) {
      throw SshConnectException(
        SshFailureReason.localNetworkUnverified,
        'Host unreachable: ${failures.join('; ')}',
      );
    }
    throw SshConnectException(
      SshFailureReason.hostUnreachable,
      'Host unreachable: ${failures.join('; ')}',
    );
  }

  /// Whether this connection cannot start for want of `ACCESS_LOCAL_NETWORK`.
  ///
  /// The permission is checked before the addresses, so a device that does not
  /// gate local traffic - or has already been granted it - never pays for a
  /// lookup.
  ///
  /// Android only: iOS cannot read the permission without raising its prompt,
  /// and dialling the address raises that prompt anyway.
  Future<bool> _blockedByLocalNetwork(List<SshEndpoint> endpoints) async {
    if (!isAndroidPlatform) return false;
    final permission = LocalNetworkPermission.instance;
    if (!await permission.isEnforced) return false;
    if (await permission.isGranted) return false;
    return allOnLocalNetwork(endpoints.map((e) => e.host));
  }

  /// Picks how the transport to [profile] is opened: straight out of the
  /// device, or as a forwarded channel over a bastion.
  ///
  /// Returning a function rather than branching per candidate is what keeps
  /// the bastion handshake outside the retry loop - it happens once, and
  /// every candidate after it is a channel on that one session.
  ///
  /// A broken chain - a loop, a missing bastion, one hop too many - is
  /// already the most specific thing that can be said, and it is the same
  /// fact at every level, so it is rethrown as-is rather than re-wrapped once
  /// per hop into a stack of "the bastion failed" sentences. Otherwise the
  /// hop itself is what failed, and which of the bastion's own reasons it was
  /// stays in the message.
  Future<TransportOpener> _transportOpener(
    SshProfile profile, {
    void Function(String message)? onConnectionLog,
    HostKeyPrompt? onHostKeyPrompt,
    KeyboardInteractivePrompt? onKeyboardInteractive,
    required int jumpDepth,
  }) async {
    final jumpHostId = profile.jumpHostProfileId;
    if (jumpHostId == null) {
      return (SshEndpoint endpoint, Duration timeout) =>
          _socketConnector(endpoint.host, endpoint.port, timeout: timeout);
    }
    if (jumpDepth >= _maxJumpDepth) {
      throw const SshConnectException(
        SshFailureReason.jumpHostConfig,
        'Too many jump hosts chained together (limit $_maxJumpDepth). '
        'Check the chain for a loop.',
      );
    }

    final bastion = await _profiles.getProfile(jumpHostId);
    if (bastion == null) {
      throw const SshConnectException(
        SshFailureReason.jumpHostConfig,
        'The jump host this profile connects through is gone.',
      );
    }
    if (bastion.id == profile.id) {
      throw const SshConnectException(
        SshFailureReason.jumpHostConfig,
        'A profile cannot be its own jump host.',
      );
    }

    onConnectionLog?.call(
      t.connectionLog.connectingThrough(name: bastion.name),
    );
    final jump = SshService(
      socketConnector: _socketConnector,
      knownHosts: _knownHosts,
      profiles: _profiles,
    );
    _jumpHost = jump;
    try {
      await jump.connect(
        bastion,
        onConnectionLog: onConnectionLog,
        onAuthMessage: onConnectionLog,
        onHostKeyPrompt: onHostKeyPrompt,
        onKeyboardInteractive: onKeyboardInteractive,
        jumpDepth: jumpDepth + 1,
      );
    } catch (error) {
      await _closeJumpHost();
      if (error is SshConnectException &&
          error.reason == SshFailureReason.jumpHostConfig) {
        rethrow;
      }
      throw SshConnectException(
        SshFailureReason.jumpHost,
        'Jump host ${bastion.name}: $error',
      );
    }
    onConnectionLog?.call(t.connectionLog.reached(name: bastion.name));

    return (SshEndpoint endpoint, Duration _) async =>
        jump.client!.forwardLocal(endpoint.host, endpoint.port);
  }

  Future<void> _closeJumpHost() async {
    final jump = _jumpHost;
    _jumpHost = null;
    await jump?.disconnect();
  }

  /// Opens the socket, then the SSH handshake, for [profile].
  ///
  /// dartssh2 starts listening on the raw socket the moment [SSHClient] is
  /// constructed, and keeps driving that listener (keepalive pings, window
  /// -adjust acks sent while processing incoming data, etc.) for the rest of
  /// the connection's life, including after this method has returned. A write
  /// against a socket the OS already aborted in the background then surfaces
  /// as an async error with no `Future` or `Stream` of ours to catch it, which
  /// would otherwise reach the top-level zone as an uncaught fatal error.
  /// Running the whole client lifetime inside one guarded zone lets late,
  /// post-connect failures (treated as the connection dying, via
  /// [onConnectionLost]) be told apart from failures during the handshake
  /// itself (still rejected normally). `keepAliveInterval` is left null
  /// because [startHealthCheck] is our own ping loop; a second one would race
  /// it on the shared global-request reply queue and desync it into phantom
  /// missed pings. [SSHHostkeyError] is what dartssh2 raises both for a
  /// signature that does not check out and for [verifyHostKey] returning
  /// false; [_hostKeyRejected] tells the common, second case apart so the
  /// message says which.
  Future<void> connect(
    SshProfile profile, {
    void Function(String message)? onAuthMessage,
    void Function(String message)? onConnectionLog,
    HostKeyPrompt? onHostKeyPrompt,
    KeyboardInteractivePrompt? onKeyboardInteractive,
    int jumpDepth = 0,
  }) async {
    _isDisposed = false;
    _promptedFor = Duration.zero;
    await connectSocket(
      profile,
      onConnectionLog: onConnectionLog,
      onHostKeyPrompt: onHostKeyPrompt,
      onKeyboardInteractive: onKeyboardInteractive,
      jumpDepth: jumpDepth,
    );

    final completer = Completer<void>();
    runZonedGuarded(
      () {
        unawaited(() async {
          try {
            final identities = await resolveIdentities(profile);
            if (_isDisposed) throw _abandoned;

            _client = SSHClient(
              _socket!,
              username: profile.username,
              algorithms: kSshAlgorithms,
              keepAliveInterval: null,
              onVerifyHostKey: (type, fingerprint) =>
                  verifyHostKey(type, fingerprint, onHostKeyPrompt),
              onPasswordRequest: profile.authMethod == AuthMethod.password
                  ? () => profile.password
                  : null,
              identities: identities,
              onUserauthBanner: onAuthMessage,
              onUserInfoRequest: (request) => answerUserInfoRequest(
                request,
                onAuthMessage,
                onKeyboardInteractive,
              ),
            );

            await _awaitAuthenticated(_client!);
            _watchTransport(_client!);
            if (!completer.isCompleted) completer.complete();
          } on SocketException catch (error) {
            _failConnect(
              completer,
              SshConnectException(
                SshFailureReason.hostUnreachable,
                'Host unreachable: ${error.message}',
              ),
            );
          } on TimeoutException {
            _failConnect(
              completer,
              const SshConnectException(
                SshFailureReason.timeout,
                'Connection timed out during authentication.',
              ),
            );
          } on SSHAuthFailError {
            _failConnect(
              completer,
              const SshConnectException(
                SshFailureReason.authFailed,
                'Authentication failed. Check your credentials.',
              ),
            );
          } on SSHAuthError catch (error) {
            _failConnect(
              completer,
              SshConnectException(
                SshFailureReason.authError,
                'Authentication error: ${error.message}',
              ),
            );
          } on SSHHostkeyError catch (error) {
            _failConnect(
              completer,
              _hostKeyRejected
                  ? const SshConnectException(
                      SshFailureReason.hostKeyRejected,
                      'Host key not accepted. The connection was not made.',
                    )
                  : SshConnectException(
                      SshFailureReason.hostKeyMismatch,
                      'Host key verification failed: ${error.message}',
                    ),
            );
          } on SshConnectException catch (error) {
            _failConnect(completer, error);
          } on SSHError catch (error) {
            _failConnect(
              completer,
              SshConnectException(
                SshFailureReason.protocol,
                'SSH error: $error',
              ),
            );
          } catch (error) {
            _failConnect(
              completer,
              SshConnectException(
                SshFailureReason.unknown,
                'Failed to connect: $error',
              ),
            );
          }
        }());
      },
      (error, stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        } else {
          onConnectionLost?.call();
        }
      },
    );
    return completer.future;
  }

  static const _abandoned = SshConnectException(
    SshFailureReason.unknown,
    'Connection cancelled.',
  );

  void _failConnect(Completer<void> completer, Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }

  /// Set when [_verifyHostKey] is the reason the handshake was torn down, so
  /// the error can say "not accepted" rather than "verification failed".
  bool _hostKeyRejected = false;

  /// Decides whether the key the server just presented is the one this device
  /// pinned for that address, and asks the user when it is not.
  ///
  /// Without this callback dartssh2 accepts every host key it is handed - the
  /// signature is checked against the key, but nothing checks that the key
  /// belongs to the machine that was asked for, which is the whole point of
  /// the exercise. Anything on the path can present its own key and read the
  /// session in clear.
  ///
  /// Fails closed: no prompt to raise means no way to establish trust, so the
  /// connection does not happen. That is what makes it safe for the
  /// background paths (a temporary client for a session list) to pass no
  /// prompt at all.
  ///
  /// Exposed for tests the same way [connectSocket] is - the decision this
  /// makes is the security boundary, and reaching it through a real handshake
  /// would mean standing up an SSH server to test it.
  @visibleForTesting
  Future<bool> verifyHostKey(
    String keyType,
    Uint8List fingerprintBytes,
    HostKeyPrompt? prompt,
  ) async {
    final endpoint = _connectedEndpoint;
    if (endpoint == null) return false;
    final fingerprint = utf8.decode(fingerprintBytes);
    final pinned = await _knownHosts.lookup(
      endpoint.host,
      endpoint.port,
      keyType,
    );
    if (pinned != null && pinned.fingerprint == fingerprint) return true;

    if (prompt == null) {
      _hostKeyRejected = true;
      return false;
    }

    final accepted = await _whilePrompting(
      () => prompt(
        HostKeyPromptRequest(
          host: endpoint.host,
          port: endpoint.port,
          keyType: keyType,
          fingerprint: fingerprint,
          verdict: pinned == null
              ? HostKeyVerdict.unknown
              : HostKeyVerdict.changed,
          pinnedFingerprint: pinned?.fingerprint,
        ),
      ),
    );
    if (!accepted) {
      _hostKeyRejected = true;
      return false;
    }

    await _knownHosts.trust(
      KnownHost(
        host: endpoint.host,
        port: endpoint.port,
        keyType: keyType,
        fingerprint: fingerprint,
        addedAt: DateTime.now(),
      ),
    );
    return true;
  }

  /// Answers a keyboard-interactive round.
  ///
  /// This is the method behind 2FA codes, PAM password prompts and expired
  /// password changes, and a server configured for it offers nothing else -
  /// so returning blanks, as this used to, locked those hosts out entirely.
  /// A round with no prompts at all is a real thing (Tailscale sends one as
  /// an informational step) and is still answered without bothering anyone.
  @visibleForTesting
  Future<List<String>?> answerUserInfoRequest(
    SSHUserInfoRequest request,
    void Function(String message)? onAuthMessage,
    KeyboardInteractivePrompt? prompt,
  ) async {
    final heading = [
      request.name,
      request.instruction,
    ].where((part) => part.trim().isNotEmpty).join('\n');
    if (heading.isNotEmpty) onAuthMessage?.call(heading);

    if (request.prompts.isEmpty) return const [];
    if (prompt == null) return null;

    return _whilePrompting(
      () => prompt(
        KeyboardInteractiveRequest(
          name: request.name,
          instruction: request.instruction,
          questions: [
            for (final question in request.prompts)
              KeyboardInteractiveQuestion(
                prompt: question.promptText,
                echo: question.echo,
              ),
          ],
        ),
      ),
    );
  }

  Future<T> _whilePrompting<T>(Future<T> Function() ask) async {
    final startedAt = DateTime.now();
    try {
      return await ask();
    } finally {
      _promptedFor += DateTime.now().difference(startedAt);
    }
  }

  /// Waits out the handshake, extending the budget by however long the user
  /// was being asked something. See [_promptedFor].
  Future<void> _awaitAuthenticated(SSHClient client) async {
    var granted = Duration.zero;
    while (true) {
      try {
        await client.authenticated.timeout(_connectionTimeout + granted);
        return;
      } on TimeoutException {
        if (_promptedFor <= granted) rethrow;
        granted = _promptedFor;
      }
    }
  }

  /// Reports a transport that closed under us the moment it happens. Without
  /// this the only signal is [startHealthCheck]'s next tick - measured at 13
  /// seconds after a server-side kill, a window in which the session still
  /// looks alive and every keystroke typed into it is dropped in silence.
  ///
  /// Our own [disconnect] closes the client too; only an unasked-for close
  /// is a lost connection.
  void _watchTransport(SSHClient client) {
    void report() {
      if (_isDisposed || _client != client) return;
      onConnectionLost?.call();
    }

    unawaited(client.done.then((_) => report(), onError: (_) => report()));
  }

  /// Detects what shell is running on the remote host.
  ///
  /// Runs `uname -s` via exec channel: exit 0 with output → [RemoteShellType.unix].
  /// `run()` never throws on a nonzero exit - a `cmd.exe`/PowerShell host
  /// happily returns a non-empty "command not found" error as its combined
  /// output, so the exit code (via `runWithResult`) is what actually tells
  /// the two apart. On failure probes for PowerShell, otherwise assumes CMD.
  Future<RemoteShellType> detectRemoteShell() async {
    final client = _client;
    if (client == null) return RemoteShellType.unknown;
    try {
      final result = await client
          .runWithResult('uname -s')
          .timeout(const Duration(seconds: 5));
      if ((result.exitCode == null || result.exitCode == 0) &&
          utf8.decode(result.stdout, allowMalformed: true).trim().isNotEmpty) {
        return RemoteShellType.unix;
      }
    } catch (_) {}
    try {
      await client
          .run(r'$PSVersionTable.PSVersion.Major')
          .timeout(const Duration(seconds: 5));
      return RemoteShellType.powershell;
    } catch (_) {
      return RemoteShellType.powershell;
    }
  }

  /// Round trips and silence on this connection, for the session to show
  /// when they are bad.
  final quality = ConnectionQuality();

  late final _pinger = KeepalivePinger(
    ping: () => _client!.ping(),
    isAlive: () => _client != null && !_client!.isClosed,
    quality: quality,
    resumable: () => _resumable,
    onLost: (cause) {
      linkLoss = cause;
      onConnectionLost?.call();
    },
  );

  /// How the keepalive found the link dead, when it was the keepalive that
  /// did; null for a transport that closed or errored on its own.
  LinkLoss? linkLoss;

  var _resumable = false;

  /// [foreground] pings often enough for a stall to show within seconds; a
  /// session nobody is looking at is pinged at the old, slower rate.
  /// [resumable] is whether the shell survives a reconnect, which is what
  /// makes giving up on a silent link early affordable.
  void startHealthCheck({bool foreground = true, bool resumable = false}) {
    _resumable = resumable;
    linkLoss = null;
    quality.reset();
    _pinger.start(foreground: foreground);
  }

  void setForeground(bool foreground) => _pinger.setForeground(foreground);

  /// Checks the link now rather than at the next keepalive; see
  /// [KeepalivePinger.probe].
  void probeConnection({bool quick = false}) => _pinger.probe(quick: quick);

  /// Measures a round trip now; see [KeepalivePinger.pingNow].
  void measureLatency() => _pinger.pingNow();

  /// Completes once the server has received everything written before it.
  /// A global request is answered in order with the channel data ahead of
  /// it, so the reply is a receipt.
  Future<void> confirmReceipt() {
    final client = _client;
    if (client == null || client.isClosed) {
      return Future.error(StateError('Not connected.'));
    }
    return client.ping();
  }

  void stopHealthCheck() => _pinger.stop();

  /// Starts an interactive shell, or runs [command] under a pty.
  ///
  /// stderr is forwarded into the same output stream as stdout rather than
  /// dropped, which would otherwise leave its errors uncaught. The shell is
  /// over once `done` completes, however it got there - a transport the OS
  /// aborted completes it with an error rather than a value, and with no
  /// `onError` that would otherwise reach the root zone as a fatal crash - so
  /// the output stream is closed either way.
  Future<SSHSession> startShell({
    int width = 80,
    int height = 24,
    String? command,
  }) async {
    final client = _client;
    if (client == null) {
      throw Exception('Not connected.');
    }

    try {
      final pty = SSHPtyConfig(
        width: width,
        height: height,
        type: 'xterm-256color',
      );
      final session = command == null
          ? await client.shell(pty: pty)
          : await client.execute(command, pty: pty);
      _session = session;

      await _stdoutSubscription?.cancel();
      _stdoutSubscription = session.stdout.listen(
        (chunk) {
          if (!_isDisposed && !_outputController.isClosed) {
            _outputController.add(chunk);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_isDisposed && !_outputController.isClosed) {
            _outputController.addError(error, stackTrace);
          }
        },
      );

      await _stderrSubscription?.cancel();
      _stderrSubscription = session.stderr.listen(
        (chunk) {
          if (!_isDisposed && !_outputController.isClosed) {
            _outputController.add(chunk);
          }
        },
        onError: (Object _, StackTrace _) {},
      );

      void closeOutput() {
        if (!_isDisposed && !_outputController.isClosed) {
          _outputController.close();
        }
      }

      unawaited(
        session.done.then((_) => closeOutput(), onError: (_) => closeOutput()),
      );

      return session;
    } catch (error) {
      throw Exception('Failed to start remote shell: $error');
    }
  }

  /// Resizes the pty, swallowing a resize (rotation, keyboard show/hide,
  /// split-view) that races a transport that just died - that throws
  /// synchronously out of dartssh2's packet writer (`SocketException` on an
  /// aborted socket, `SSHStateError` once it is fully closed) and, uncaught,
  /// would reach the root zone as a fatal crash over a resize nobody asked to
  /// be durable.
  void resizeTerminal(int width, int height) {
    try {
      _session?.resizeTerminal(width, height);
    } catch (_) {
      onConnectionLost?.call();
    }
  }

  /// Writes [data], swallowing the same failure [resizeTerminal] does: a
  /// keystroke whose transport died between typing and sending throws out of
  /// dartssh2's packet writer. Nothing useful can be done with it at that
  /// point, and the health check is already on its way to noticing; crashing
  /// over one lost character is not the answer.
  void write(Uint8List data) {
    try {
      _session?.write(data);
    } catch (_) {
      onConnectionLost?.call();
    }
  }

  Future<void> startLocalForward(
    String ruleId,
    int localPort,
    String remoteHost,
    int remotePort,
  ) async {
    final client = _client;
    if (client == null) throw Exception('Not connected.');

    final serverSocket = await ServerSocket.bind('127.0.0.1', localPort);
    _localListeners[ruleId] = serverSocket;

    serverSocket.listen((socket) {
      client
          .forwardLocal(remoteHost, remotePort)
          .then((forward) {
            unawaited(
              socket.cast<List<int>>().pipe(forward.sink).catchError((_) {}),
            );
            unawaited(
              forward.stream.cast<List<int>>().pipe(socket).catchError((_) {
                socket.destroy();
              }),
            );
          })
          .catchError((_) {
            socket.destroy();
          });
    });
  }

  Future<void> startRemoteForward(
    String ruleId,
    int remotePort,
    String localHost,
    int localPort,
  ) async {
    final client = _client;
    if (client == null) throw Exception('Not connected.');

    final forward = await client.forwardRemote(port: remotePort);
    if (forward == null) {
      throw Exception('Server refused remote forwarding on port $remotePort.');
    }

    _remoteForwards[ruleId] = forward;

    // ignore: cancel_subscriptions - subscription cancelled in stopRemoteForward
    final sub = forward.connections.listen((connection) {
      Socket.connect(localHost, localPort)
          .then((socket) {
            unawaited(
              connection.stream.cast<List<int>>().pipe(socket).catchError((_) {
                socket.destroy();
              }),
            );
            unawaited(
              socket.cast<List<int>>().pipe(connection.sink).catchError((_) {}),
            );
          })
          .catchError((_) {
            connection.destroy();
          });
    });
    _remoteForwardSubs[ruleId] = sub;
  }

  void stopLocalForward(String ruleId) {
    _localListeners.remove(ruleId)?.close();
  }

  void stopRemoteForward(String ruleId) {
    _remoteForwardSubs.remove(ruleId)?.cancel();
    final forward = _remoteForwards.remove(ruleId);
    if (forward != null) {
      _client?.cancelForwardRemote(forward);
    }
  }

  void stopAllForwards() {
    for (final id in _localListeners.keys.toList()) {
      _localListeners.remove(id)?.close();
    }
    for (final id in _remoteForwardSubs.keys.toList()) {
      _remoteForwardSubs.remove(id)?.cancel();
    }
    for (final forward in _remoteForwards.values.toList()) {
      _client?.cancelForwardRemote(forward);
    }
    _remoteForwards.clear();
  }

  /// Tears down the transport and everything riding on it.
  ///
  /// The client's own close is not awaited: since dartssh2 3.0.0 it awaits
  /// the transport's own `socket.close()`, which is the unbounded half-close
  /// wait [_closeSocket] exists to cap - its `destroy()` ends this one too.
  /// Detached, an error here would surface as uncaught, and a socket being
  /// torn down has none worth reporting. The jump host closes after the
  /// socket, not before: the forwarded channel is carried by this session, so
  /// tearing the carrier down first would leave the channel closing against
  /// nothing. The session's own close is guarded like [write] and
  /// [resizeTerminal]: a transport that is already dying throws synchronously
  /// out of dartssh2's packet writer, and that must not stop the rest of the
  /// teardown from running.
  Future<void> disconnect() async {
    _isDisposed = true;
    stopHealthCheck();
    stopAllForwards();
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    try {
      _session?.close();
    } catch (_) {}
    _session = null;

    final client = _client;
    _client = null;
    if (client != null) unawaited(client.close().catchError((_) {}));

    await _closeSocket();
    await _closeJumpHost();

    if (!_outputController.isClosed) {
      await _outputController.close();
    }
  }

  /// Hangs up the socket without letting it hold anything up.
  ///
  /// `Socket.close()` half-closes and its future only completes once the peer
  /// closes back - on the radio that just went away, that is never. This is
  /// awaited from the reconnect path (`disconnectSession` runs before the new
  /// transport is built), so an unbounded wait here is a reconnect that never
  /// starts, on exactly the dead transport it exists to replace. The graceful
  /// close gets a moment; [SSHSocket.destroy] then ends it either way.
  Future<void> _closeSocket() async {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    try {
      await socket.close().timeout(_socketCloseTimeout);
    } catch (_) {}
    try {
      socket.destroy();
    } catch (_) {}
  }
}
