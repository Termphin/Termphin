import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/sftp/sftp_service.dart';
import 'package:termphin/widgets/sftp/sftp_folder_picker.dart';

import '../../support/sftp_fakes.dart';
import '../../support/test_app.dart';

const _desktop = TargetPlatformVariant({TargetPlatform.linux});

/// Opens the picker the way a copy or move does and shows what it returned.
class _Host extends StatefulWidget {
  const _Host(this.sftp);

  final SftpService sftp;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String _result = 'none';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () async {
            final picked = await showSftpFolderPicker(
              context: context,
              sftp: widget.sftp,
              title: 'Move to',
              actionLabel: 'Move here',
              startPath: '/home/user',
              canChoose: (folder) => folder != '/home/user',
              canEnter: (folder) => !folder.endsWith('/locked'),
            );
            setState(() => _result = picked ?? 'cancelled');
          },
          child: const Text('open'),
        ),
        Text('result: $_result'),
      ],
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  final sftp = SftpService(
    FakeSftpSshClient(
      FakeSftpClient(
        FakeSftpTree({
          '/home/user': [sftpDir('alpha'), sftpDir('beta'), sftpDir('locked')],
          '/home/user/alpha': [sftpDir('inner')],
          '/home/user/beta': [],
          '/home/user/alpha/inner': [],
        }),
      ),
    ),
  );
  await sftp.init();
  await pumpTestApp(tester, _Host(sftp));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a click only puts the cursor on a folder; the second opens it', (
    tester,
  ) async {
    await _open(tester);

    await tester.tap(find.text('alpha'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('inner'), findsNothing);

    await tester.tap(find.text('alpha'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();
    expect(find.text('inner'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('the arrows and Enter walk into a folder, Enter on no row takes '
      'it', (tester) async {
    await _open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('inner'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('result: /home/user/alpha'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('Ctrl+Enter takes the folder shown with the cursor on a row', (
    tester,
  ) async {
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('result: /home/user/alpha'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('Enter does not take a folder that cannot be the destination', (
    tester,
  ) async {
    await _open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('result: none'), findsOneWidget);
    expect(find.text('Move to'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('a folder that cannot be entered stays shut under Enter', (
    tester,
  ) async {
    await _open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('locked'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('Backspace goes up a folder', (tester) async {
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('inner'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(find.text('beta'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('Cancel and Esc both leave without a folder', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('result: cancelled'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('result: cancelled'), findsOneWidget);
    expect(find.text('Move to'), findsNothing);
  }, variant: _desktop);

  testWidgets('a phone still opens a folder on one tap and has no Cancel', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();

    expect(find.text('inner'), findsOneWidget);
  });
}
