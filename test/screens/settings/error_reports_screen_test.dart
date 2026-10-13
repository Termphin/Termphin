import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/error_reports_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/screens/settings/error_reports_screen.dart';
import 'package:termphin/services/app/error_reports.dart';
import 'package:termphin/services/app/identity_anonymizer.dart';
import 'package:termphin/services/settings/anonymize_setting.dart';
import 'package:termphin/services/settings/app_settings.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  late ErrorReports reports;
  late SshProfile profile;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
    reports = ErrorReports();
    profile = profileFixture(host: 'prod.example.com');
    container = ProviderContainer.test(
      overrides: [
        errorReportsProvider.overrideWithValue(reports),
        profilesProvider.overrideWith(() => _StubProfiles([profile])),
      ],
    );
  });

  testWidgets('says so when nothing was recorded', (tester) async {
    await pumpTestApp(tester, const ErrorReportsScreen(), container: container);

    expect(find.text('No errors recorded'), findsOneWidget);
  });

  testWidgets('lists a recorded error with its repeat count', (tester) async {
    await reports.record(StateError('boom'), null);
    await reports.record(StateError('boom'), null);

    await pumpTestApp(tester, const ErrorReportsScreen(), container: container);

    expect(find.text('Bad state: boom'), findsOneWidget);
    expect(find.textContaining('2 times'), findsOneWidget);
  });

  testWidgets('scrubs saved hosts out of an error when anonymized', (
    tester,
  ) async {
    await anonymizeSetting.set(true);
    await reports.record(StateError('cannot reach prod.example.com'), null);

    await pumpTestApp(tester, const ErrorReportsScreen(), container: container);

    expect(find.textContaining('prod.example.com'), findsNothing);
    expect(
      find.textContaining(IdentityAnonymizer.host(profile.id)),
      findsOneWidget,
    );
  });
}

class _StubProfiles extends ProfilesNotifier {
  _StubProfiles(this.initial);

  final List<SshProfile> initial;

  @override
  List<SshProfile> build() => initial;
}
