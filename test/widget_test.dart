import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/screens/home_screen.dart';
import 'package:termphin/screens/search/global_search_launcher.dart';
import 'package:termphin/widgets/profiles/profile_avatar.dart';
import 'package:termphin/widgets/profiles/profile_card.dart';

import 'support/fixtures.dart';
import 'support/test_app.dart';

class _EmptyProfilesNotifier extends ProfilesNotifier {
  @override
  List<SshProfile> build() => const [];
}

class _ProfilesNotifier extends ProfilesNotifier {
  @override
  List<SshProfile> build() => [profileFixture()];
}

void main() {
  testWidgets('HomeScreen renders its primary controls', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final container = ProviderContainer.test(
      overrides: [profilesProvider.overrideWith(_EmptyProfilesNotifier.new)],
    );

    await pumpTestApp(tester, const HomeScreen(), container: container);
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(GlobalSearchLauncher), findsNothing);
    expect(find.widgetWithText(TextField, 'user@host'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('No machines yet'), findsOneWidget);
    expect(find.text('Add your first machine'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('ProfileCard exposes profile actions from its menu', (
    tester,
  ) async {
    var editOpened = false;

    await pumpTestApp(
      tester,
      Scaffold(
        body: ProfileCard(
          profile: profileFixture(),
          onTap: () {},
          onEdit: () => editOpened = true,
          onLoadSessions: () {},
          onDelete: () {},
        ),
      ),
    );

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(editOpened, isTrue);
  });

  testWidgets('Machine avatars use a tinted gradient', (tester) async {
    await pumpTestApp(
      tester,
      const ProfileAvatar(iconName: 'desktop', colorHex: '4DA3FF'),
    );

    final avatarContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(ProfileAvatar),
        matching: find.byType(Container),
      ),
    );
    final decoration = avatarContainer.decoration! as BoxDecoration;

    expect(decoration.color, const Color(0xFF4DA3FF).withValues(alpha: 0.15));
    expect(decoration.gradient, isA<LinearGradient>());
    expect(decoration.border, isNotNull);
    expect(find.byType(ProfileAvatarGlyph), findsOneWidget);
  });

  testWidgets('HomeScreen separates search and machine content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    final container = ProviderContainer.test(
      overrides: [profilesProvider.overrideWith(_ProfilesNotifier.new)],
    );

    await pumpTestApp(tester, const HomeScreen(), container: container);
    await tester.pumpAndSettle();

    expect(find.byType(GlobalSearchLauncher), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsOneWidget);
  });
}
