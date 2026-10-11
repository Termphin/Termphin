import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/platform/share_intent_service.dart';
import 'package:termphin/services/sftp/upload_plan.dart';
import 'package:termphin/widgets/share/share_preview.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  LocalUpload file(String name, int? size) => LocalUpload(
    name: name,
    open: () => const Stream.empty(),
    length: () async => size,
  );

  testWidgets('one file: a tile with its name and size', (tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: SharePreview(content: SharedContent([file('a.pdf', 2048)])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.share.uploadTo.toUpperCase()), findsOneWidget);
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
  });

  testWidgets('several files: how many, and a tile for each', (tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: SharePreview(
          content: SharedContent([file('a.pdf', 2048), file('b.jpg', null)]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(t.share.uploadManyTo(count: 2).toUpperCase()),
      findsOneWidget,
    );
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('b.jpg'), findsOneWidget);
    expect(find.text('0 B'), findsNothing);
  });
}
