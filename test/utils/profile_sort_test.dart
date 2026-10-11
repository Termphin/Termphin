import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/utils/profile_sort.dart';

import '../support/fixtures.dart';

void main() {
  final connectedToday = profileFixture(
    id: 'b',
    name: 'Beta',
    createdAt: DateTime.utc(2020),
    lastConnectedAt: DateTime.utc(2026, 5),
  );
  final addedYesterday = profileFixture(
    id: 'a',
    name: 'Alpha',
    createdAt: DateTime.utc(2026, 4),
  );

  test('recently used puts the newest first, connected or not', () {
    final sorted = sortProfiles([addedYesterday, connectedToday]);
    expect(sorted.map((p) => p.id), ['b', 'a']);
  });

  test('ties break on name', () {
    final sameDay = DateTime.utc(2026, 4);
    final sorted = sortProfiles([
      profileFixture(id: 'z', name: 'Zulu', createdAt: sameDay),
      profileFixture(id: 'a', name: 'Alpha', createdAt: sameDay),
    ]);
    expect(sorted.map((p) => p.id), ['a', 'z']);
  });

  test('by name, both ways', () {
    final input = [connectedToday, addedYesterday];
    expect(sortProfiles(input, ProfileSort.nameAZ).map((p) => p.id), [
      'a',
      'b',
    ]);
    expect(sortProfiles(input, ProfileSort.nameZA).map((p) => p.id), [
      'b',
      'a',
    ]);
  });

  test('leaves the list it was handed alone', () {
    final input = [addedYesterday, connectedToday];
    sortProfiles(input);
    expect(input.map((p) => p.id), ['a', 'b']);
  });
}
