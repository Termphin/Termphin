/// Trims both [a] and [b] and compares them case-insensitively.
bool isSameGroup(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

/// Returns the known group's own spelling when one matches [recordGroup] under
/// [isSameGroup], and `null` when none does.
String? resolveGroupName(String recordGroup, Iterable<String> knownGroups) {
  for (final known in knownGroups) {
    if (isSameGroup(recordGroup, known)) {
      return known;
    }
  }
  return null;
}
