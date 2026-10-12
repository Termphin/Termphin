import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/completion/remote_completion.dart';

/// [completeCommand]'s bash script run by the bash on this machine, without
/// bash-completion, so the plain file fallback answers: what a host gets.
void main() {
  final hasBash =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v bash']).exitCode == 0;

  late Directory home;

  setUp(() {
    home = Directory(
      Directory.systemTemp
          .createTempSync('termphin_bash_')
          .resolveSymbolicLinksSync(),
    );
    Directory('${home.path}/Projects').createSync();
    Directory('${home.path}/work/My Docs/sub').createSync(recursive: true);
    File('${home.path}/work/My Docs/a.txt').createSync();
    Directory('${home.path}/work/src').createSync();
    File('${home.path}/cwd').writeAsStringSync('${home.path}/work');
  });

  tearDown(() => home.deleteSync(recursive: true));

  Future<Uint8List> complete(String line) async {
    final result = await Process.run(
      'sh',
      ['-c', completeCommand(CompletionEngine.bash, line, cwdFile: 'cwd')],
      environment: {'HOME': home.path},
      stdoutEncoding: null,
    );
    return Uint8List.fromList(result.stdout as List<int>);
  }

  test('a ~/ path keeps its ~ and a directory its slash', () async {
    expect(parseCandidates(await complete('cd ~/Proj')), ['~/Projects/']);
  }, skip: !hasBash);

  test('an escaped or quoted blank stays inside the word', () async {
    const inside = ['My Docs/a.txt', 'My Docs/sub/'];
    expect(parseCandidates(await complete(r'cat My\ Docs/')), inside);
    expect(parseCandidates(await complete("cat 'My Docs/")), inside);
  }, skip: !hasBash);

  test('what follows an = is completed on its own', () async {
    expect(parseCandidates(await complete('tar --file=')), contains('src/'));
  }, skip: !hasBash);

  test('the answer says which directory it completed in', () async {
    final output = await complete('ls ');

    expect(completionDirectory(output), '${home.path}/work');
    expect(parseCandidates(output), isNot(contains(startsWith('@@'))));
  }, skip: !hasBash);
}
