import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/known_host.dart';
import 'package:termphin/screens/settings/known_hosts_screen.dart';
import 'package:termphin/services/app/identity_anonymizer.dart';
import 'package:termphin/services/settings/anonymize_setting.dart';
import 'package:termphin/services/storage/known_hosts_store.dart';
import 'package:termphin/widgets/ui/empty_state.dart';

import '../../support/fake_master_key_store.dart';
import '../../support/secure_storage_channel.dart';
import '../../support/test_app.dart';

KnownHost _host({
  String host = 'example.com',
  int port = 22,
  String keyType = 'ssh-ed25519',
  String fingerprint = 'SHA256:aaa',
}) => KnownHost(
  host: host,
  port: port,
  keyType: keyType,
  fingerprint: fingerprint,
  addedAt: DateTime(2026, 3, 4),
);

/// The cached `SharedPreferences` instance is a static future, so it belongs
/// to whichever test first awaited it; every later test in its own fake
/// clock would then be waiting on a zone that no longer runs anything, which
/// is why `setUp` resets that static before each one.
void main() {
  final t = AppLocale.en.buildSync();

  late KnownHostsStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    SharedPreferences.resetStatic();
  });

  /// A store of its own per test, built here in the test body rather than in
  /// `setUp`.
  ///
  /// Both halves matter. Not `KnownHostsStore.instance`, because its write
  /// queue is one chain for the life of the process and an unfinished write
  /// blocks every later one. And not `setUp` either: the queue starts from a
  /// `Future.value()` created wherever the store is, and a future schedules
  /// its continuations in its own zone - one built outside the fake clock
  /// never runs the action a `testWidgets` body queues onto it, so the write
  /// silently never happens.
  void useOwnStore() {
    store = KnownHostsStore(cipher: cipherFixture());
  }

  Future<void> seed(KnownHost host) => store.trust(host);

  Future<void> pump(WidgetTester tester) async {
    await pumpTestApp(tester, KnownHostsScreen(store: store));
    await tester.pumpAndSettle();
  }

  testWidgets('says so when nothing has been pinned yet', (tester) async {
    useOwnStore();
    await pump(tester);
    expect(find.byType(EmptyStatePanel), findsOneWidget);
    expect(find.text(t.settings.knownHostsEmpty), findsOneWidget);
    expect(find.text(t.settings.knownHostsForget), findsNothing);
  });

  testWidgets('lists a pinned key with everything needed to check it', (
    tester,
  ) async {
    useOwnStore();
    await seed(_host(fingerprint: 'SHA256:theOneThisDevicePinned'));
    await pump(tester);

    expect(find.text('example.com:22'), findsOneWidget);
    expect(find.text('SHA256:theOneThisDevicePinned'), findsOneWidget);
    expect(
      find.textContaining('ssh-ed25519'),
      findsOneWidget,
      reason: 'the key type is half of what a pin is keyed by',
    );
    expect(
      find.textContaining(DateFormat.yMMMd().format(DateTime(2026, 3, 4))),
      findsOneWidget,
    );
  });

  testWidgets('anonymize hides the real host, not the port', (tester) async {
    useOwnStore();
    await anonymizeSetting.set(true);
    addTearDown(() => anonymizeSetting.set(false));
    await seed(_host());
    await pump(tester);

    expect(
      find.text('${IdentityAnonymizer.host('example.com')}:22'),
      findsOneWidget,
    );
    expect(find.textContaining('example.com'), findsNothing);

    await tester.tap(find.text(t.settings.knownHostsForget));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('${IdentityAnonymizer.host('example.com')}:22'),
      findsWidgets,
    );
    expect(find.textContaining('example.com'), findsNothing);
  });

  testWidgets('lists one card per key type on the same address', (
    tester,
  ) async {
    useOwnStore();
    await seed(_host(keyType: 'ssh-ed25519', fingerprint: 'SHA256:ed'));
    await seed(_host(keyType: 'ssh-rsa', fingerprint: 'SHA256:rsa'));
    await pump(tester);

    expect(find.text('example.com:22'), findsNWidgets(2));
    expect(find.text('SHA256:ed'), findsOneWidget);
    expect(find.text('SHA256:rsa'), findsOneWidget);
  });

  testWidgets('forgetting asks first, and cancelling keeps the pin', (
    tester,
  ) async {
    useOwnStore();
    await seed(_host());
    await pump(tester);

    await tester.tap(find.text(t.settings.knownHostsForget));
    await tester.pumpAndSettle();
    expect(find.text(t.settings.knownHostsForgetTitle), findsOneWidget);
    expect(
      find.textContaining('example.com:22'),
      findsWidgets,
      reason: 'the dialog names which host it is about',
    );

    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();

    expect(await store.entries(), hasLength(1));
    expect(find.text('SHA256:aaa'), findsOneWidget);
  });

  testWidgets('confirming un-pins it and the list stops showing it', (
    tester,
  ) async {
    useOwnStore();
    await seed(_host());
    await pump(tester);

    await tester.tap(find.text(t.settings.knownHostsForget));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.knownHostsForget).last);
    await tester.pumpAndSettle();

    expect(await store.entries(), isEmpty);
    expect(find.byType(EmptyStatePanel), findsOneWidget);
    expect(find.text(t.settings.knownHostsForgotten), findsOneWidget);
  });

  testWidgets('forgets only the key type on the row that was tapped', (
    tester,
  ) async {
    useOwnStore();
    await seed(_host(keyType: 'ssh-ed25519', fingerprint: 'SHA256:ed'));
    await seed(_host(keyType: 'ssh-rsa', fingerprint: 'SHA256:rsa'));
    await pump(tester);

    await tester.tap(find.text(t.settings.knownHostsForget).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.knownHostsForget).last);
    await tester.pumpAndSettle();

    final left = await store.entries();
    expect(left, hasLength(1));
    expect(left.single.keyType, 'ssh-rsa');
    expect(find.text('SHA256:rsa'), findsOneWidget);
    expect(find.text('SHA256:ed'), findsNothing);
  });

  testWidgets('leaves other addresses alone', (tester) async {
    useOwnStore();
    await seed(_host(host: 'a.example.com', fingerprint: 'SHA256:a'));
    await seed(_host(host: 'b.example.com', fingerprint: 'SHA256:b'));
    await pump(tester);

    await tester.tap(find.text(t.settings.knownHostsForget).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.knownHostsForget).last);
    await tester.pumpAndSettle();

    final left = await store.entries();
    expect(left, hasLength(1));
    expect(left.single.host, 'b.example.com');
  });

  testWidgets('an un-pinned host is unknown again, not still trusted', (
    tester,
  ) async {
    useOwnStore();
    await seed(_host(fingerprint: 'SHA256:old'));
    await pump(tester);

    await tester.tap(find.text(t.settings.knownHostsForget));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.knownHostsForget).last);
    await tester.pumpAndSettle();

    expect(
      await store.check(
        'example.com',
        22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:new',
      ),
      HostKeyVerdict.unknown,
    );
  });
}
