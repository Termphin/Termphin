import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/sftp/sftp_service.dart';
import 'package:termphin/widgets/sftp/sftp_folder_picker.dart';

import '../../support/sftp_fakes.dart';
import '../../support/test_app.dart';

void main() {
  testWidgets(
    'a slower folder listing does not overwrite a faster, newer one',
    (tester) async {
      final tree = FakeSftpTree({
        '/home/user': [sftpDir('a'), sftpDir('b')],
        '/home/user/a': [sftpDir('old')],
        '/home/user/b': [sftpDir('new')],
      });
      final fakeSftp = FakeSftpClient(tree);
      final sftp = SftpService(FakeSftpSshClient(fakeSftp));
      await sftp.init();

      String? chosen;
      await pumpTestApp(
        tester,
        SftpFolderPicker(
          sftp: sftp,
          title: 'Move to',
          actionLabel: 'Move here',
          startPath: '/home/user',
          canChoose: (_) => true,
          canEnter: (_) => true,
          onChoose: (path) => chosen = path,
        ),
      );
      await tester.pumpAndSettle();

      fakeSftp.gateListing('/home/user/a');
      await tester.tap(find.text('a'));
      await tester.pump();

      await tester.tap(find.text('b'));
      await tester.pumpAndSettle();

      expect(find.text('new'), findsOneWidget);
      expect(find.text('/home/user/b'), findsOneWidget);

      fakeSftp.releaseListing('/home/user/a');
      await tester.pumpAndSettle();

      expect(find.text('new'), findsOneWidget);
      expect(find.text('old'), findsNothing);
      expect(find.text('/home/user/b'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Move here'));
      await tester.pumpAndSettle();

      expect(chosen, '/home/user/b');
    },
  );
}
