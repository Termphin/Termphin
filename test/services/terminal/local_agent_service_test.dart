import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/ssh/remote_agent_service.dart';
import 'package:termphin/services/terminal/local_agent_service.dart';

class _TestAssets extends CachingAssetBundle {
  _TestAssets({
    required this.version,
    required this.protocol,
    required this.linuxBinary,
    required this.windowsBinary,
  });

  final String version;
  final int protocol;
  final Uint8List linuxBinary;
  final Uint8List windowsBinary;

  @override
  Future<ByteData> load(String key) async {
    if (key == '$kAgentAssetDirectory/manifest.properties') {
      final manifest =
          'version=$version\n'
          'protocol=$protocol\n'
          'x86_64.file=termphin-agent-x86_64.gz\n'
          'x86_64.sha256=${agentSha256(linuxBinary)}\n'
          'windows_x86_64.file=termphin-agent-windows-x86_64.exe.gz\n'
          'windows_x86_64.sha256=${agentSha256(windowsBinary)}\n';
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(manifest)));
    }
    if (key == '$kAgentAssetDirectory/termphin-agent-x86_64.gz') {
      return ByteData.sublistView(Uint8List.fromList(gzip.encode(linuxBinary)));
    }
    if (key == '$kAgentAssetDirectory/termphin-agent-windows-x86_64.exe.gz') {
      return ByteData.sublistView(
        Uint8List.fromList(gzip.encode(windowsBinary)),
      );
    }
    throw FlutterError('Missing asset: $key');
  }
}

void main() {
  late Directory tempHome;
  late Uint8List linuxHelper;
  late Uint8List windowsHelper;
  late _TestAssets assets;

  setUp(() async {
    tempHome = await Directory.systemTemp.createTemp('local_agent_test_');
    linuxHelper = Uint8List.fromList(utf8.encode('#!/bin/sh\necho linux\n'));
    windowsHelper = Uint8List.fromList(utf8.encode('MZ-windows-helper'));
    assets = _TestAssets(
      version: '0.21.0',
      protocol: 1,
      linuxBinary: linuxHelper,
      windowsBinary: windowsHelper,
    );
  });

  tearDown(() async {
    if (await tempHome.exists()) {
      await tempHome.delete(recursive: true);
    }
  });

  test('supportsLocalSessionsVersion gates on 0.21.0', () {
    expect(supportsLocalSessionsVersion(null), isFalse);
    expect(supportsLocalSessionsVersion('Unreleased'), isFalse);
    expect(supportsLocalSessionsVersion('0.20.1'), isFalse);
    expect(supportsLocalSessionsVersion('0.21.0'), isTrue);
    expect(supportsLocalSessionsVersion('0.22.3'), isTrue);
  });

  test(
    'installs missing Linux agent, chmods 755, and writes agent.meta',
    () async {
      final commands = <(String, List<String>)>[];
      final service = LocalAgentService(
        assets: assets,
        operatingSystem: 'Linux',
        architecture: 'x86_64',
        homeDirectory: tempHome.path,
        runProcess: (executable, arguments) async {
          commands.add((executable, arguments));
          if (arguments.length == 2 &&
              arguments[0] == 'version' &&
              arguments[1] == '--machine') {
            return ProcessResult(0, 0, 'version=0.21.0\nprotocol=1\n', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final binPath = await service.ensureInstalled();

      expect(File(binPath).readAsBytesSync(), linuxHelper);
      expect(
        File(service.metadataPath!).readAsStringSync(),
        'version=0.21.0\nprotocol=1\nsha256=${agentSha256(linuxHelper)}\n',
      );
      expect(
        commands.any(
          (c) => c.$1 == 'chmod' && c.$2.length == 2 && c.$2[0] == '755',
        ),
        isTrue,
      );
    },
  );

  test('upgrades an older installed Linux agent', () async {
    final service = LocalAgentService(
      assets: assets,
      operatingSystem: 'Linux',
      architecture: 'x86_64',
      homeDirectory: tempHome.path,
      runProcess: (executable, arguments) async {
        if (arguments.join(' ') == 'version --machine') {
          final current = File(executable).readAsBytesSync();
          final version = agentSha256(current) == agentSha256(linuxHelper)
              ? '0.21.0'
              : '0.20.1';
          return ProcessResult(0, 0, 'version=$version\nprotocol=1\n', '');
        }
        return ProcessResult(0, 0, '', '');
      },
    );

    final oldBytes = Uint8List.fromList(utf8.encode('old-binary'));
    await Directory(service.installDirectoryPath!).create(recursive: true);
    await File(service.binaryPath!).writeAsBytes(oldBytes);
    await File(service.metadataPath!).writeAsString(
      'version=0.20.1\nprotocol=1\nsha256=${agentSha256(oldBytes)}\n',
    );

    await service.ensureInstalled();

    expect(File(service.binaryPath!).readAsBytesSync(), linuxHelper);
    expect(
      File(service.metadataPath!).readAsStringSync(),
      contains('version=0.21.0'),
    );
  });

  test('leaves the same installed agent untouched', () async {
    final commands = <(String, List<String>)>[];
    final service = LocalAgentService(
      assets: assets,
      operatingSystem: 'Linux',
      architecture: 'x86_64',
      homeDirectory: tempHome.path,
      runProcess: (executable, arguments) async {
        commands.add((executable, arguments));
        return ProcessResult(0, 0, 'version=0.21.0\nprotocol=1\n', '');
      },
    );

    final sentinel = Uint8List.fromList(utf8.encode('already-installed'));
    await Directory(service.installDirectoryPath!).create(recursive: true);
    await File(service.binaryPath!).writeAsBytes(sentinel);
    await File(service.metadataPath!).writeAsString(
      'version=0.21.0\nprotocol=1\nsha256=${agentSha256(linuxHelper)}\n',
    );

    await service.ensureInstalled();

    expect(File(service.binaryPath!).readAsBytesSync(), sentinel);
    expect(commands.where((c) => c.$1 == 'chmod'), isEmpty);
  });

  test('keeps a newer installed agent untouched', () async {
    final commands = <(String, List<String>)>[];
    final service = LocalAgentService(
      assets: assets,
      operatingSystem: 'Linux',
      architecture: 'x86_64',
      homeDirectory: tempHome.path,
      runProcess: (executable, arguments) async {
        commands.add((executable, arguments));
        return ProcessResult(0, 0, 'version=0.25.0\nprotocol=1\n', '');
      },
    );

    final newerBytes = Uint8List.fromList(utf8.encode('newer-binary'));
    await Directory(service.installDirectoryPath!).create(recursive: true);
    await File(service.binaryPath!).writeAsBytes(newerBytes);
    await File(service.metadataPath!).writeAsString(
      'version=0.25.0\nprotocol=1\nsha256=${agentSha256(newerBytes)}\n',
    );

    await service.ensureInstalled();

    expect(File(service.binaryPath!).readAsBytesSync(), newerBytes);
    expect(commands.where((c) => c.$1 == 'chmod'), isEmpty);
  });

  test(
    'Windows upgrade deletes stale .old.exe, renames running exe and writes new one',
    () async {
      final commands = <(String, List<String>)>[];
      final service = LocalAgentService(
        assets: assets,
        operatingSystem: 'Windows',
        architecture: 'AMD64',
        homeDirectory: tempHome.path,
        runProcess: (executable, arguments) async {
          commands.add((executable, arguments));
          if (arguments.join(' ') == 'version --machine') {
            final current = File(executable).readAsBytesSync();
            final version = agentSha256(current) == agentSha256(windowsHelper)
                ? '0.21.0'
                : '0.20.1';
            return ProcessResult(0, 0, 'version=$version\nprotocol=1\n', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final oldBytes = Uint8List.fromList(utf8.encode('old-exe'));
      await Directory(service.installDirectoryPath!).create(recursive: true);
      await File(service.binaryPath!).writeAsBytes(oldBytes);
      await File(service.metadataPath!).writeAsString(
        'version=0.20.1\nprotocol=1\nsha256=${agentSha256(oldBytes)}\n',
      );
      final staleOld = File(
        '${service.installDirectoryPath}${Platform.pathSeparator}termphin-agent.old.exe',
      );
      await staleOld.writeAsString('stale');

      await service.ensureInstalled();

      expect(File(service.binaryPath!).readAsBytesSync(), windowsHelper);
      expect(await staleOld.exists(), isFalse);
      expect(commands.where((c) => c.$1 == 'chmod'), isEmpty);
    },
  );

  test(
    'list, kill, rename and deviceCommand invoke the local binary directly',
    () async {
      final calls = <(String, List<String>)>[];
      final service = LocalAgentService(
        assets: assets,
        operatingSystem: 'Linux',
        architecture: 'x86_64',
        homeDirectory: tempHome.path,
        runProcess: (executable, arguments) async {
          calls.add((executable, arguments));
          if (arguments.first == 'list') {
            return ProcessResult(
              0,
              0,
              'work\t1\t1700000000\t1\tdev1\tidle\n',
              '',
            );
          }
          if (arguments.join(' ') == 'version --machine') {
            return ProcessResult(0, 0, 'version=0.21.0\nprotocol=1\n', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      await Directory(service.installDirectoryPath!).create(recursive: true);
      await File(service.binaryPath!).writeAsBytes(linuxHelper);
      await File(service.metadataPath!).writeAsString(
        'version=0.21.0\nprotocol=1\nsha256=${agentSha256(linuxHelper)}\n',
      );

      final listed = await service.list();
      expect(listed.map((s) => s.name), ['work']);

      await service.kill('work');
      await service.rename('work', 'play');
      await service.deviceCommand('take', 'play', 'dev-9');

      expect(calls.map((c) => c.$2).toList(), [
        ['list'],
        ['kill', 'work'],
        ['version', '--machine'],
        ['rename', 'work', 'play'],
        ['take', 'play', 'dev-9'],
      ]);
    },
  );
}
