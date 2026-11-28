import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/remote_agent_status.dart';
import '../../models/session_tab.dart';
import '../app/version_compare.dart';
import '../realtime/presence_state.dart';
import '../ssh/remote_agent_service.dart';
import 'remote_mux_commands.dart';

/// Minimum bundled `termphin-agent` version required for local desktop
/// sessions over `--stdio`.
const localSessionsSinceVersion = '0.21.0';

/// Returns whether a bundled agent [version] supports local stdio sessions.
bool supportsLocalSessionsVersion(String? version) {
  if (version == null || !isReleasedVersion(version)) return false;
  return compareVersions(version, localSessionsSinceVersion) >= 0;
}

/// Runs a short-lived local process with argv.
typedef LocalProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Manages the local `termphin-agent` installation on desktop hosts and runs
/// its short-lived subcommands (`list`, `kill`, `rename`, `take|away|back`)
/// directly as local processes without SSH.
class LocalAgentService {
  LocalAgentService({
    LocalProcessRunner? runProcess,
    AssetBundle? assets,
    String? operatingSystem,
    String? architecture,
    Map<String, String>? environment,
    String? homeDirectory,
  }) : _runProcess = runProcess ?? _defaultRunProcess,
       _assets = assets ?? rootBundle,
       _operatingSystem = _resolveOperatingSystem(operatingSystem),
       _rawArchitecture = _resolveArchitecture(
         architecture,
         operatingSystem: _resolveOperatingSystem(operatingSystem),
         environment: environment ?? Platform.environment,
       ),
       _environment = environment ?? Platform.environment,
       _homeDirectory = homeDirectory;

  static Future<ProcessResult> _defaultRunProcess(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments);

  static String _resolveOperatingSystem(String? override) {
    if (override != null) return override;
    return switch (Platform.operatingSystem) {
      'linux' => 'Linux',
      'macos' => 'Darwin',
      'windows' => 'Windows',
      final other => other,
    };
  }

  static String _resolveArchitecture(
    String? override, {
    required String operatingSystem,
    required Map<String, String> environment,
  }) {
    if (override != null) return override;
    if (operatingSystem == 'Windows') {
      final processor = environment['PROCESSOR_ARCHITECTURE'];
      if (processor != null && processor.isNotEmpty) return processor;
    }
    final match = RegExp(r'on "[^_]+_([^"]+)"').firstMatch(Platform.version);
    return match?.group(1) ?? '';
  }

  final LocalProcessRunner _runProcess;
  final AssetBundle _assets;
  final String _operatingSystem;
  final String _rawArchitecture;
  final Map<String, String> _environment;
  final String? _homeDirectory;

  /// Whether the target host OS is Windows.
  bool get isWindows => _operatingSystem == 'Windows';

  /// The user's home directory on this computer, where local sessions start.
  String? get homeDirectoryPath => _home;

  String? get _home {
    final raw =
        _homeDirectory ??
        (isWindows ? _environment['USERPROFILE'] : _environment['HOME']);
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Directory where the local agent binary and `agent.meta` live.
  String? get installDirectoryPath {
    final home = _home;
    if (home == null) return null;
    if (_operatingSystem != 'Linux' &&
        _operatingSystem != 'Darwin' &&
        _operatingSystem != 'Windows') {
      return null;
    }
    final sep = Platform.pathSeparator;
    final cleanHome = home.endsWith(sep) || home.endsWith('/')
        ? home.substring(0, home.length - 1)
        : home;
    final rel = isWindows
        ? kAgentRelativeDirectoryWindows
        : kAgentRelativeDirectoryPosix;
    return '$cleanHome$sep${rel.replaceAll('/', sep)}';
  }

  /// Full path to the local `termphin-agent` binary, or `null` if unavailable.
  String? get binaryPath {
    final dir = installDirectoryPath;
    if (dir == null) return null;
    final name = isWindows ? kAgentBinaryNameWindows : kAgentBinaryNamePosix;
    return '$dir${Platform.pathSeparator}$name';
  }

  /// Full path to `agent.meta` beside [binaryPath], or `null` if unavailable.
  String? get metadataPath {
    final dir = installDirectoryPath;
    if (dir == null) return null;
    return '$dir${Platform.pathSeparator}$kAgentMetadataName';
  }

  /// Ensures the local `termphin-agent` binary is installed and up to date,
  /// returning its path. Leaves any newer already-installed binary untouched.
  Future<String> ensureInstalled() async {
    final dirPath = installDirectoryPath;
    final binPath = binaryPath;
    final metaPath = metadataPath;
    if (dirPath == null || binPath == null || metaPath == null) {
      throw Exception('Local Termphin helper directory is unavailable.');
    }
    final arch = normalizeAgentArchitecture(_rawArchitecture);
    if (arch == null) {
      throw Exception('Unsupported local CPU architecture.');
    }
    final bundle = await bundledAgent(_operatingSystem, arch, assets: _assets);
    if (bundle == null) {
      throw Exception(
        'No Termphin helper is bundled for $_operatingSystem on $arch.',
      );
    }

    final state = await _probeState(
      binPath: binPath,
      metaPath: metaPath,
      bundle: bundle,
    );
    if (state == RemoteAgentState.current || state == RemoteAgentState.newer) {
      return binPath;
    }

    final bytes = await loadBundledHelper(
      _assets,
      '$kAgentAssetDirectory/${bundle.fileName}',
    );
    if (agentSha256(bytes) != bundle.sha256) {
      throw Exception('Bundled Termphin helper failed its SHA-256 check.');
    }

    await Directory(dirPath).create(recursive: true);

    final sep = Platform.pathSeparator;
    final binaryName = isWindows
        ? kAgentBinaryNameWindows
        : kAgentBinaryNamePosix;
    final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final binaryTemp = File('$dirPath$sep$binaryName.tmp-$nonce');
    final metaTemp = File('$dirPath$sep$kAgentMetadataName.tmp-$nonce');

    try {
      await binaryTemp.writeAsBytes(bytes, flush: true);
      final writtenBytes = await binaryTemp.readAsBytes();
      if (agentSha256(writtenBytes) != bundle.sha256) {
        throw Exception('Local Termphin helper failed its SHA-256 check.');
      }

      if (!isWindows) {
        final chmodResult = await _runProcess('chmod', [
          '755',
          binaryTemp.path,
        ]);
        _throwOnFailure(chmodResult, 'Failed to mark local helper executable.');
      }

      final metadata = utf8.encode(
        'version=${bundle.version}\n'
        'protocol=${bundle.protocol}\n'
        'sha256=${bundle.sha256}\n',
      );
      await metaTemp.writeAsBytes(metadata, flush: true);

      if (isWindows) {
        final existing = File(binPath);
        if (await existing.exists()) {
          final oldFile = File('$dirPath${sep}termphin-agent.old.exe');
          try {
            if (await oldFile.exists()) {
              await oldFile.delete();
            }
          } catch (_) {}
          await existing.rename(oldFile.path);
        }
      }

      await binaryTemp.rename(binPath);
      await metaTemp.rename(metaPath);

      if (isWindows) {
        try {
          final oldFile = File('$dirPath${sep}termphin-agent.old.exe');
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (_) {}
      }

      final verify = await _runProcess(binPath, const ['version', '--machine']);
      _throwOnFailure(verify, 'Local helper verification failed.');
      return binPath;
    } catch (_) {
      try {
        if (await binaryTemp.exists()) await binaryTemp.delete();
      } catch (_) {}
      try {
        if (await metaTemp.exists()) await metaTemp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<RemoteAgentState> _probeState({
    required String binPath,
    required String metaPath,
    required BundledAgent bundle,
  }) async {
    final binFile = File(binPath);
    if (!await binFile.exists()) {
      return RemoteAgentState.missing;
    }

    String? localVersion;
    int? localProtocol;
    try {
      final result = await _runProcess(binPath, const ['version', '--machine']);
      if (result.exitCode == 0) {
        final values = parseAgentProperties(_stdoutText(result));
        localVersion = values['version'];
        localProtocol = int.tryParse(values['protocol'] ?? '');
      }
    } catch (_) {}

    String? metaVersion;
    int? metaProtocol;
    String? metaSha;
    try {
      final metaFile = File(metaPath);
      if (await metaFile.exists()) {
        final meta = parseAgentProperties(await metaFile.readAsString());
        metaVersion = meta['version'];
        metaProtocol = int.tryParse(meta['protocol'] ?? '');
        metaSha = meta['sha256'];
      }
    } catch (_) {}

    final metadataMatches =
        metaVersion == localVersion && metaProtocol == localProtocol;
    final verifiedSha =
        metadataMatches &&
            metaSha != null &&
            RegExp(r'^[a-f0-9]{64}$').hasMatch(metaSha)
        ? metaSha
        : null;

    return classifyAgentState(
      binaryExists: true,
      remoteVersion: localVersion,
      remoteProtocol: localProtocol,
      remoteSha256: verifiedSha,
      bundle: bundle,
    );
  }

  /// Runs a short-lived shell [command] on this computer (`sh -c` on POSIX,
  /// `cmd /c` on Windows) so local machines can share setup and probe
  /// commands with SSH hosts.
  Future<Uint8List> runShellCommand(String command) async {
    final result = isWindows
        ? await _runProcess('cmd', ['/c', command])
        : await _runProcess('sh', ['-c', command]);
    final stdout = _stdoutText(result);
    final stderr = _stderrText(result);
    final combined = switch ((stdout.isEmpty, stderr.isEmpty)) {
      (true, true) => '',
      (false, true) => stdout,
      (true, false) => stderr,
      (false, false) => '$stdout\n$stderr',
    };
    return Uint8List.fromList(utf8.encode(combined));
  }

  /// Lists local `termphin-agent` sessions, or an empty list if the helper is
  /// not installed yet.
  Future<List<RemoteMuxSession>> list() async {
    final binPath = binaryPath;
    if (binPath == null || !await File(binPath).exists()) {
      return const [];
    }
    final result = await _runProcess(binPath, const ['list']);
    _throwOnFailure(result, 'Failed to list local sessions.');
    final text = _stdoutText(result);
    presence.value = parseAgentSessionLines(text);
    return const RemoteMuxCommands().parseSessionList(
      text,
      Multiplexer.termphin,
    );
  }

  /// What each local session is doing and who is attached to it, as the
  /// last [list] read it; null before the first. Live status shows it on
  /// the session rows, the way it shows a server's report.
  final ValueNotifier<List<PresenceSession>?> presence = ValueNotifier(null);

  /// Kills the local session named [name].
  Future<void> kill(String name) async {
    final binPath = await _installedOrEnsureBinary();
    final result = await _runProcess(binPath, ['kill', name]);
    _throwOnFailure(result, 'Failed to end the local session.');
  }

  /// Renames local session [oldName] to [newName].
  Future<void> rename(String oldName, String newName) async {
    if (SessionTab.validateName(newName) != null) {
      throw Exception('Session name contains unsupported characters.');
    }
    final binPath = await ensureInstalled();
    final result = await _runProcess(binPath, ['rename', oldName, newName]);
    _throwOnFailure(result, 'Failed to rename the local session.');
  }

  /// Runs a `take`, `away`, or `back` device command for session [name].
  Future<void> deviceCommand(String verb, String name, String deviceId) async {
    final binPath = await _installedOrEnsureBinary();
    final result = await _runProcess(binPath, [verb, name, deviceId]);
    _throwOnFailure(result, 'Failed to run local device command.');
  }

  Future<String> _installedOrEnsureBinary() async {
    final path = binaryPath;
    if (path != null && await File(path).exists()) return path;
    return ensureInstalled();
  }

  String _stdoutText(ProcessResult result) {
    final raw = result.stdout;
    if (raw is String) return raw;
    if (raw is List<int>) return utf8.decode(raw, allowMalformed: true);
    return raw?.toString() ?? '';
  }

  String _stderrText(ProcessResult result) {
    final raw = result.stderr;
    if (raw is String) return raw.trim();
    if (raw is List<int>) return utf8.decode(raw, allowMalformed: true).trim();
    return raw?.toString().trim() ?? '';
  }

  void _throwOnFailure(ProcessResult result, String fallback) {
    if (result.exitCode == 0) return;
    final message = _stderrText(result);
    throw Exception(message.isEmpty ? fallback : message);
  }
}
