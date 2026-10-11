import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/terminal_overlay_provider.dart';

import '../support/fixtures.dart';

void main() {
  test('shows and hides a terminal session', () {
    final container = ProviderContainer.test();
    final notifier = container.read(terminalOverlayProvider.notifier);
    final profile = profileFixture();

    expect(container.read(terminalOverlayProvider), isNull);

    notifier.show('session-1', profile);
    expect(container.read(terminalOverlayProvider)?.$1, 'session-1');
    expect(container.read(terminalOverlayProvider)?.$2, same(profile));

    notifier.hide();
    expect(container.read(terminalOverlayProvider), isNull);
  });

  test('re-showing the same session notifies again', () {
    final container = ProviderContainer.test();
    final notifier = container.read(terminalOverlayProvider.notifier);
    final profile = profileFixture();

    final seen = <(String, SshProfile, SiblingScope)?>[];
    container.listen(terminalOverlayProvider, (_, next) => seen.add(next));

    notifier.show('session-1', profile, scope: SiblingScope.none);
    notifier.show('session-1', profile, scope: SiblingScope.none);

    expect(seen.length, 2);
  });
}
