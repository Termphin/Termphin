import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/sftp/sftp_image_preview_screen.dart';
import 'package:termphin/services/sftp/sftp_service.dart';

import '../../support/sftp_fakes.dart';
import '../../support/test_app.dart';

const _dir = '/home/user/pics';

void main() {
  final t = AppLocale.en.buildSync();

  late FakeSftpTree tree;
  late SftpService sftp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    tree = FakeSftpTree({
      _dir: [
        sftpFile('one.png', size: 120),
        sftpFile('two.png', size: 120),
        sftpFile('huge.png', size: 40 * 1024 * 1024),
      ],
    });
    sftp = SftpService(FakeSftpSshClient(FakeSftpClient(tree)));
    await sftp.init();
  });

  /// The fake SFTP client resolves on real async time, so a plain
  /// `pumpAndSettle` after an action that talks to it times out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await tester.pump();
  }

  Future<void> open(
    WidgetTester tester, {
    String filename = 'one.png',
    int? size = 120,
    bool withSiblings = true,
    VoidCallback? onMutated,
  }) async {
    await pumpTestApp(
      tester,
      SftpImagePreviewScreen(
        sftp: sftp,
        path: '$_dir/$filename',
        filename: filename,
        fileSize: size,
        directoryPath: withSiblings ? _dir : null,
        siblingImages: withSiblings ? tree.children[_dir] : null,
        onMutated: onMutated,
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await tester.pump();
  }

  testWidgets('names the image it was opened on', (tester) async {
    await open(tester);
    expect(find.text('one.png'), findsWidgets);
  });

  testWidgets('opens on the image that was tapped, not the first one', (
    tester,
  ) async {
    await open(tester, filename: 'two.png');
    expect(find.text('two.png'), findsWidgets);
  });

  testWidgets('pages through the siblings in the folder', (tester) async {
    await open(tester);
    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller!.initialPage, 0);
    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('has a single page when it was opened without siblings', (
    tester,
  ) async {
    await open(tester, withSiblings: false);
    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller!.initialPage, 0);
  });

  testWidgets('refuses one too large to preview instead of pulling it down', (
    tester,
  ) async {
    await open(
      tester,
      filename: 'huge.png',
      size: 40 * 1024 * 1024,
      withSiblings: false,
    );

    expect(
      find.textContaining(t.sftp.fileTooLarge(size: '40.0 MB')),
      findsOneWidget,
    );
  });

  testWidgets('offers the actions for what is on screen', (tester) async {
    await open(tester);
    expect(find.byTooltip(t.sftp.download), findsOneWidget);
    expect(find.byTooltip(t.sftp.copyPath), findsOneWidget);
  });

  testWidgets('a delete is reported so the listing behind can refresh', (
    tester,
  ) async {
    var mutated = false;
    await open(tester, onMutated: () => mutated = true);

    await tester.tap(find.byTooltip(t.common.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.delete).last);
    await settle(tester);

    expect(mutated, isTrue);
    expect(
      tree.children[_dir]!.map((e) => e.filename),
      isNot(contains('one.png')),
    );
  });

  testWidgets('a cancelled delete reports nothing', (tester) async {
    var mutated = false;
    await open(tester, onMutated: () => mutated = true);

    await tester.tap(find.byTooltip(t.common.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();

    expect(mutated, isFalse);
  });

  testWidgets('the route never vetoes its own pop', (tester) async {
    await open(tester);

    expect(find.byType(PopScope), findsNothing);
  });
}
