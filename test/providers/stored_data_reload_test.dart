import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/snippets_provider.dart';
import 'package:termphin/providers/ssh_keys_provider.dart';
import 'package:termphin/providers/stored_data_reload.dart';

import '../support/fakes.dart';

void main() {
  test('a reload after an import refreshes the keys too', () async {
    final container = ProviderContainer.test(
      overrides: [
        profileStorageProvider.overrideWithValue(FakeProfileStorage()),
        groupStorageProvider.overrideWithValue(FakeGroupStorage()),
        snippetStorageProvider.overrideWithValue(FakeSnippetStorage()),
      ],
    );
    final before = container.read(sshKeysRevisionProvider);

    await reloadStoredData(container.read);

    expect(container.read(sshKeysRevisionProvider), before + 1);
  });
}
