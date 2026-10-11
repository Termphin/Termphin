/// Whether [version] is a released one, which is to say a dotted number this
/// file can compare at all.
///
/// `release_notes.yaml` and `whats_new.yaml` both carry an `Unreleased` entry
/// while work lands and nobody has decided what version ships it. Everything
/// that reads those files orders by [compareVersions], so an entry it cannot
/// parse has to be dropped before it gets there rather than throwing halfway
/// through the changelog screen.
bool isReleasedVersion(String version) =>
    version.split('.').every((part) => int.tryParse(part) != null);

/// Compares dotted numeric versions ("1.2.3"), shorter ones padded with
/// zeroes so "1.2" and "1.2.0" are equal.
///
/// Shared by the changelog and the what's-new highlights - both decide what
/// a device has already seen the same way, and two copies of this would only
/// agree until one of them was edited.
int compareVersions(String a, String b) {
  final partsA = a.split('.').map(int.parse).toList();
  final partsB = b.split('.').map(int.parse).toList();
  for (var i = 0; i < partsA.length || i < partsB.length; i++) {
    final valueA = i < partsA.length ? partsA[i] : 0;
    final valueB = i < partsB.length ? partsB[i] : 0;
    if (valueA != valueB) return valueA.compareTo(valueB);
  }
  return 0;
}
