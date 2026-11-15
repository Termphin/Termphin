import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/services/account/account_photos.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/widgets/account/account_avatar.dart';

import '../../support/test_app.dart';

/// A picture already on the device, handed over without touching the disk
/// inside the test's fake clock.
class _KeptPhoto extends AccountPhotos {
  _KeptPhoto(this.file);

  final File file;

  @override
  Future<File?> fileFor(String url) => SynchronousFuture(file);
}

void main() {
  late Directory root;
  late AccountPhotos photos;

  const user = AccountUser(
    uid: 'u',
    provider: AccountProvider.github,
    email: 'octo@example.com',
    photoUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('account_avatar');
    final file = File('${root.path}/photo.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
        ),
      );
    photos = _KeptPhoto(file);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> show(WidgetTester tester, {bool anonymize = false}) async {
    await pumpTestApp(
      tester,
      Center(
        child: AccountAvatar(user: user, photos: photos, anonymize: anonymize),
      ),
    );
    await tester.pump();
  }

  testWidgets('the account picture replaces the letter once it is there', (
    tester,
  ) async {
    await show(tester);

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('O'), findsNothing);
  });

  testWidgets('anonymized, the picture stays hidden behind a dot', (
    tester,
  ) async {
    await show(tester, anonymize: true);

    expect(find.byType(Image), findsNothing);
    expect(find.text('•'), findsOneWidget);
  });

  testWidgets('without a picture the letter stays', (tester) async {
    await pumpTestApp(
      tester,
      const Center(
        child: AccountAvatar(
          user: AccountUser(
            uid: 'u',
            provider: AccountProvider.password,
            email: 'octo@example.com',
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('O'), findsOneWidget);
  });
}
