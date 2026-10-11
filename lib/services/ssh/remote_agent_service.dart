import 'dart:convert';
import 'dart:io' show gzip;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

import '../../models/remote_agent_status.dart';

const _assetDirectory = 'assets/termphin-agent';
const _remoteRelativeDirectory = '.local/lib/termphin';
const _remoteRelativeDirectoryWindows = 'AppData/Local/termphin/bin';
const _remoteBinaryName = 'termphin-agent';
const _remoteBinaryNameWindows = 'termphin-agent.exe';
const _remoteMetadataName = 'agent.meta';

String shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

/// Double quotes work in both `cmd.exe` and PowerShell, whichever
/// Win32-OpenSSH's `DefaultShell` turns out to be. Only the binary path
/// (which can contain spaces under `%LOCALAPPDATA%`) ever needs this - the
/// session name is restricted to a safe character set by the agent itself.
String windowsQuote(String value) => '"${value.replaceAll('"', '""')}"';

String _powerShellQuote(String script) => "'${script.replaceAll("'", "''")}'";

/// Wraps [script] as a `powershell -EncodedCommand` command line. Base64
/// UTF-16LE survives re-tokenizing by whatever `DefaultShell` is - cmd.exe
/// unless changed, which reads PowerShell's `&` as a syntax error.
/// [interactive] drops `-NonInteractive`, for the attach that owns the pty.
String powerShellCommandLine(String script, {bool interactive = false}) {
  final utf16leBytes = Uint8List(script.length * 2);
  for (var i = 0; i < script.length; i++) {
    final unit = script.codeUnitAt(i);
    utf16leBytes[i * 2] = unit & 0xFF;
    utf16leBytes[i * 2 + 1] = (unit >> 8) & 0xFF;
  }
  final encoded = base64.encode(utf16leBytes);
  final flags = interactive ? '-NoProfile' : '-NoProfile -NonInteractive';
  return 'powershell $flags -EncodedCommand $encoded';
}

class DartRemoteAgentStatus {
  const DartRemoteAgentStatus({
    required this.publicStatus,
    this.home,
    this.binaryPath,
    this.operatingSystem,
    this.rawArchitecture,
  });

  final RemoteAgentStatus publicStatus;
  final String? home;
  final String? binaryPath;
  final String? operatingSystem;
  final String? rawArchitecture;

  bool get supported => publicStatus.supported;
  bool get usable =>
      binaryPath != null &&
      publicStatus.remoteVersion != null &&
      publicStatus.remoteProtocol != null;
}

class RemoteAgentService {
  const RemoteAgentService();

  /// Probes [client]'s host for an installed agent, POSIX first.
  ///
  /// A Windows host's default shell (cmd.exe, or PowerShell if reconfigured)
  /// doesn't know `/bin/sh` at all and fails outright rather than leaving
  /// fields empty - that failure is what triggers the PowerShell probe, the
  /// same way `/bin/sh -c` is tried unconditionally rather than trusting
  /// whatever the login shell is.
  Future<DartRemoteAgentStatus> probe(SSHClient client) async {
    final posixResult = await _runPosix(client, '''
home=\$HOME
dir="\$home/$_remoteRelativeDirectory"
bin="\$dir/$_remoteBinaryName"
meta="\$dir/$_remoteMetadataName"
printf 'home=%s\\n' "\$home"
printf 'os=%s\\n' "\$(uname -s 2>/dev/null || true)"
printf 'arch=%s\\n' "\$(uname -m 2>/dev/null || true)"
if [ -x "\$bin" ]; then
  printf 'binary=1\\n'
  "\$bin" version --machine 2>/dev/null | while IFS= read -r line; do
    printf 'binary.%s\\n' "\$line"
  done
else
  printf 'binary=0\\n'
fi
if [ -r "\$meta" ]; then
  while IFS= read -r line; do
    printf 'meta.%s\\n' "\$line"
  done < "\$meta"
fi
''');
    final posixValues = _parseProperties(
      utf8.decode(posixResult.stdout, allowMalformed: true),
    );
    if (posixResult.exitCode == 0 && (posixValues['os'] ?? '').isNotEmpty) {
      return _statusFromProbe(
        values: posixValues,
        operatingSystem: posixValues['os'] ?? '',
        binaryName: _remoteBinaryName,
        relativeDirectory: _remoteRelativeDirectory,
      );
    }

    final windowsResult = await _runPowerShell(client, '''
\$h = \$env:USERPROFILE
\$dir = "\$h/$_remoteRelativeDirectoryWindows"
\$bin = "\$dir/$_remoteBinaryNameWindows"
\$meta = "\$dir/$_remoteMetadataName"
Write-Output "home=\$h"
Write-Output "os=Windows"
Write-Output "arch=\$env:PROCESSOR_ARCHITECTURE"
if (Test-Path \$bin) {
  Write-Output "binary=1"
  & \$bin version --machine 2>\$null | ForEach-Object { Write-Output "binary.\$_" }
} else {
  Write-Output "binary=0"
}
if (Test-Path \$meta) {
  Get-Content \$meta | ForEach-Object { Write-Output "meta.\$_" }
}
''');
    final windowsValues = _parseProperties(
      utf8.decode(windowsResult.stdout, allowMalformed: true),
    );
    return _statusFromProbe(
      values: windowsValues,
      operatingSystem: windowsValues['os'] ?? '',
      binaryName: _remoteBinaryNameWindows,
      relativeDirectory: _remoteRelativeDirectoryWindows,
    );
  }

  Future<DartRemoteAgentStatus> _statusFromProbe({
    required Map<String, String> values,
    required String operatingSystem,
    required String binaryName,
    required String relativeDirectory,
  }) async {
    final home = values['home']?.trim();
    final rawArchitecture = values['arch'] ?? '';
    final architecture = _normalizeArchitecture(rawArchitecture);
    final bundle = architecture == null
        ? null
        : await _bundledAgent(operatingSystem, architecture);
    if ((operatingSystem != 'Linux' &&
            operatingSystem != 'Windows' &&
            operatingSystem != 'Darwin') ||
        bundle == null ||
        home == null ||
        home.isEmpty) {
      return DartRemoteAgentStatus(
        home: home,
        operatingSystem: operatingSystem,
        rawArchitecture: rawArchitecture,
        publicStatus: RemoteAgentStatus(
          state: RemoteAgentState.unsupported,
          supported: false,
          architecture: architecture ?? rawArchitecture,
          operatingSystem: operatingSystem.isEmpty ? null : operatingSystem,
          bundledVersion: bundle?.version,
          bundledSha256: bundle?.sha256,
          bundledProtocol: bundle?.protocol,
        ),
      );
    }

    final binaryExists = values['binary'] == '1';
    final remoteVersion = values['binary.version'];
    final remoteProtocol = int.tryParse(values['binary.protocol'] ?? '');
    final metadataVersion = values['meta.version'];
    final metadataProtocol = int.tryParse(values['meta.protocol'] ?? '');
    final metadataSha = values['meta.sha256'];
    final metadataMatches =
        metadataVersion == remoteVersion && metadataProtocol == remoteProtocol;
    final remoteSha =
        metadataMatches &&
            metadataSha != null &&
            RegExp(r'^[a-f0-9]{64}$').hasMatch(metadataSha)
        ? metadataSha
        : null;
    final state = _classify(
      binaryExists: binaryExists,
      remoteVersion: remoteVersion,
      remoteProtocol: remoteProtocol,
      remoteSha256: remoteSha,
      bundle: bundle,
    );
    final binaryPath = '$home/$relativeDirectory/$binaryName';
    return DartRemoteAgentStatus(
      home: home,
      operatingSystem: operatingSystem,
      rawArchitecture: rawArchitecture,
      binaryPath: binaryExists ? binaryPath : null,
      publicStatus: RemoteAgentStatus(
        state: state,
        supported: true,
        architecture: architecture,
        operatingSystem: operatingSystem,
        bundledVersion: bundle.version,
        bundledSha256: bundle.sha256,
        bundledProtocol: bundle.protocol,
        remoteVersion: remoteVersion,
        remoteSha256: remoteSha,
        remoteProtocol: remoteProtocol,
      ),
    );
  }

  /// [probed] hands over a probe the caller already paid for. The attach path
  /// runs one immediately before this to decide whether the host is supported
  /// at all, and a second one costs another round trip on the critical path
  /// to learn what the first already said.
  Future<DartRemoteAgentStatus> ensureForAttach(
    SSHClient client, {
    DartRemoteAgentStatus? probed,
  }) async {
    final status = probed ?? await probe(client);
    if (!status.supported) {
      final os = status.operatingSystem?.trim();
      final arch = status.rawArchitecture?.trim();
      final detected = [
        if (os != null && os.isNotEmpty) 'os=$os',
        if (arch != null && arch.isNotEmpty) 'arch=$arch',
        if (status.home == null || status.home!.isEmpty) 'home=<empty>',
      ].join(' ');
      throw Exception(
        'Termphin sessions support Linux, Windows and macOS on arm64/x86_64 hosts.'
        '${detected.isEmpty ? ' The remote probe returned no output.' : ' Detected: $detected.'}',
      );
    }
    return switch (status.publicStatus.state) {
      RemoteAgentState.missing ||
      RemoteAgentState.repair ||
      RemoteAgentState.updateAvailable => install(client, current: status),
      _ => status,
    };
  }

  /// Uploads the bundled agent to [client]'s host and activates it.
  ///
  /// The helpers ship gzipped: App Store validation refuses any Mach-O
  /// inside the app bundle - the macOS helpers were rejected by name - even
  /// though nothing here ever runs on the device, it is bytes on their way
  /// to the user's own server. Compressed, they are data rather than
  /// executables, and the bundle is about half the size. The digest checked
  /// against [_BundledAgent.sha256] is of the helper itself, not of the
  /// archive, so it is the same value the remote copy is checked against
  /// after upload.
  Future<DartRemoteAgentStatus> install(
    SSHClient client, {
    DartRemoteAgentStatus? current,
  }) async {
    final existing = current ?? await probe(client);
    final architecture = existing.publicStatus.architecture;
    final home = existing.home;
    final operatingSystem = existing.operatingSystem;
    if (architecture == null) {
      throw Exception('Unsupported remote CPU architecture.');
    }
    if (home == null || home.isEmpty) {
      throw Exception('The remote HOME directory is unavailable.');
    }
    final isWindows = operatingSystem == 'Windows';
    final binaryName = isWindows ? _remoteBinaryNameWindows : _remoteBinaryName;
    final relativeDirectory = isWindows
        ? _remoteRelativeDirectoryWindows
        : _remoteRelativeDirectory;
    final bundle = await _bundledAgent(operatingSystem ?? '', architecture);
    if (bundle == null) {
      throw Exception(
        'No Termphin helper is bundled for $operatingSystem on $architecture.',
      );
    }
    final data = await rootBundle.load('$_assetDirectory/${bundle.fileName}');
    final packed = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final bytes = bundle.fileName.endsWith('.gz')
        ? Uint8List.fromList(gzip.decode(packed))
        : packed;
    if (_sha256(bytes) != bundle.sha256) {
      throw Exception('Bundled Termphin helper failed its SHA-256 check.');
    }

    final remoteDirectory = '$home/$relativeDirectory';
    final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final binaryTemp = '$binaryName.upload-$nonce';
    final metadataTemp = '$_remoteMetadataName.upload-$nonce';

    final prepare = isWindows
        ? await _runPowerShell(
            client,
            'New-Item -ItemType Directory -Force -Path '
            '${_powerShellQuote(remoteDirectory)} | Out-Null',
          )
        : await _runPosix(
            client,
            'umask 077; mkdir -p ${shellQuote(remoteDirectory)}; '
            'chmod 700 ${shellQuote(remoteDirectory)}',
          );
    _throwOnFailure(prepare, 'Failed to prepare the remote helper directory.');

    final metadata = utf8.encode(
      'version=${bundle.version}\n'
      'protocol=${bundle.protocol}\n'
      'sha256=${bundle.sha256}\n',
    );
    final sftp = await client.sftp();
    try {
      await _writeRemoteFile(sftp, '$remoteDirectory/$binaryTemp', bytes);
      await _writeRemoteFile(
        sftp,
        '$remoteDirectory/$metadataTemp',
        Uint8List.fromList(metadata),
      );
    } finally {
      await sftp.close();
    }

    try {
      final activate = isWindows
          ? await _runPowerShell(client, '''
\$ErrorActionPreference = 'Stop'
\$dir = ${_powerShellQuote(remoteDirectory)}
# Not -Filter: its DOS-style wildcards are unreliable on a name this dotted.
Get-ChildItem -LiteralPath \$dir -ErrorAction SilentlyContinue | Where-Object { \$_.Name -like "$binaryName.old-*" } | Remove-Item -Force -ErrorAction SilentlyContinue
if (Test-Path "\$dir/$binaryName") {
  Rename-Item -Force "\$dir/$binaryName" "\$dir/$binaryName.old-$nonce"
}
Move-Item -Force "\$dir/$binaryTemp" "\$dir/$binaryName"
Move-Item -Force "\$dir/$metadataTemp" "\$dir/$_remoteMetadataName"
# Guarded, and never last: a Remove-Item that finds nothing leaves \$? false,
# which powershell.exe reports as exit 1 even though the install worked.
if (Test-Path "\$dir/$binaryName.old-$nonce") {
  Remove-Item -Force -ErrorAction SilentlyContinue "\$dir/$binaryName.old-$nonce"
}
& "\$dir/$binaryName" version --machine
''')
          : await _runPosix(client, '''
set -e
dir=${shellQuote(remoteDirectory)}
chmod 700 "\$dir/$binaryTemp"
mv -f "\$dir/$binaryTemp" "\$dir/$binaryName"
mv -f "\$dir/$metadataTemp" "\$dir/$_remoteMetadataName"
"\$dir/$binaryName" version --machine
''');
      _throwOnFailure(activate, 'Remote helper install failed.');
    } catch (error) {
      if (isWindows) {
        await _runPowerShell(
          client,
          'Remove-Item -Force -ErrorAction SilentlyContinue '
          '"$remoteDirectory/$binaryTemp", "$remoteDirectory/$metadataTemp"',
        );
      } else {
        await _runPosix(
          client,
          'rm -f ${shellQuote('$remoteDirectory/$binaryTemp')} '
          '${shellQuote('$remoteDirectory/$metadataTemp')}',
        );
      }
      rethrow;
    }

    final installed = await probe(client);
    if (installed.publicStatus.state != RemoteAgentState.current) {
      throw Exception('Remote helper verification failed after upload.');
    }
    return installed;
  }

  Future<void> _writeRemoteFile(
    SftpClient sftp,
    String path,
    Uint8List bytes,
  ) async {
    final file = await sftp.open(
      path,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      await file.writeBytes(bytes);
    } finally {
      await file.close();
    }
  }

  /// Runs [script] through `/bin/sh` so hosts whose login shell is not
  /// POSIX-compatible (fish, csh) still execute it correctly.
  Future<SSHRunResult> _runPosix(SSHClient client, String script) =>
      client.runWithResult('/bin/sh -c ${shellQuote(script)}');

  /// Runs [script] through PowerShell regardless of Win32-OpenSSH's
  /// `DefaultShell` setting (cmd.exe by default) - the Windows counterpart
  /// of [_runPosix] always going through `/bin/sh`. See
  /// [powerShellCommandLine] for why the script is encoded rather than
  /// quoted.
  Future<SSHRunResult> _runPowerShell(SSHClient client, String script) =>
      client.runWithResult(powerShellCommandLine(script));

  void _throwOnFailure(SSHRunResult result, String fallback) {
    if (result.exitCode == null || result.exitCode == 0) return;
    final message = utf8.decode(result.stderr, allowMalformed: true).trim();
    throw Exception(message.isEmpty ? fallback : message);
  }
}

class _BundledAgent {
  const _BundledAgent({
    required this.architecture,
    required this.fileName,
    required this.version,
    required this.protocol,
    required this.sha256,
  });

  final String architecture;
  final String fileName;
  final String version;
  final int protocol;
  final String sha256;
}

/// Null when nothing is bundled for this OS and CPU (ARM64 Windows, say) -
/// unsupported, not broken, so probe reports rather than throws.
Future<_BundledAgent?> _bundledAgent(
  String operatingSystem,
  String architecture,
) async {
  final manifest = _parseProperties(
    await rootBundle.loadString('$_assetDirectory/manifest.properties'),
  );
  final manifestKey = switch (operatingSystem) {
    'Windows' => 'windows_$architecture',
    'Darwin' => 'macos_$architecture',
    _ => architecture,
  };
  final fileName = manifest['$manifestKey.file'];
  final sha256 = manifest['$manifestKey.sha256'];
  final version = manifest['version'];
  final protocol = int.tryParse(manifest['protocol'] ?? '');
  if (version == null || protocol == null) {
    throw Exception('Bundled helper manifest is invalid.');
  }
  if (fileName == null || sha256 == null) {
    return null;
  }
  return _BundledAgent(
    architecture: architecture,
    fileName: fileName,
    version: version,
    protocol: protocol,
    sha256: sha256,
  );
}

Map<String, String> _parseProperties(String value) => {
  for (final line in const LineSplitter().convert(value))
    if (line.trim().isNotEmpty &&
        !line.trimLeft().startsWith('#') &&
        line.contains('='))
      line.substring(0, line.indexOf('=')).trim(): line
          .substring(line.indexOf('=') + 1)
          .trim(),
};

String? _normalizeArchitecture(String value) => switch (value) {
  'x86_64' || 'amd64' || 'AMD64' => 'x86_64',
  'aarch64' || 'arm64' || 'ARM64' => 'aarch64',
  _ when value.startsWith('armv8') => 'aarch64',
  _ => null,
};

RemoteAgentState _classify({
  required bool binaryExists,
  required String? remoteVersion,
  required int? remoteProtocol,
  required String? remoteSha256,
  required _BundledAgent bundle,
}) {
  if (!binaryExists) return RemoteAgentState.missing;
  if (remoteVersion == null || remoteProtocol == null || remoteSha256 == null) {
    return RemoteAgentState.repair;
  }
  if (remoteProtocol != bundle.protocol) return RemoteAgentState.repair;
  if (remoteSha256 == bundle.sha256) return RemoteAgentState.current;
  if (_compareVersions(remoteVersion, bundle.version) > 0) {
    return RemoteAgentState.newer;
  }
  return RemoteAgentState.updateAvailable;
}

int _compareVersions(String first, String second) {
  final left = first.split(RegExp(r'[-.+]'));
  final right = second.split(RegExp(r'[-.+]'));
  for (var index = 0; index < left.length || index < right.length; index++) {
    final a = int.tryParse(index < left.length ? left[index] : '') ?? 0;
    final b = int.tryParse(index < right.length ? right[index] : '') ?? 0;
    if (a != b) return a.compareTo(b);
  }
  return 0;
}

String _sha256(Uint8List bytes) => SHA256Digest()
    .process(bytes)
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();
