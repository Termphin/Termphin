import '../models/ssh_profile.dart';

/// The orders a list of machines can be put in.
enum ProfileSort { recentlyUsed, nameAZ, nameZA }

/// [profiles] in [sort] order, as a new list.
///
/// Shared because every list of machines in the app is the same list: the home
/// screen, the sheet that opens a new session, and the snippet run screen all
/// have to agree on which machine is first, or the same set reads as a
/// different one depending on where it is being looked at.
///
/// A machine that has never been connected to sorts on when it was added, and
/// ties break on name - two machines added in the same import would otherwise
/// come back in whatever order storage happened to hand over.
List<SshProfile> sortProfiles(
  List<SshProfile> profiles, [
  ProfileSort sort = ProfileSort.recentlyUsed,
]) {
  final sorted = [...profiles];
  switch (sort) {
    case ProfileSort.recentlyUsed:
      sorted.sort((a, b) {
        final aDate = a.lastConnectedAt ?? a.createdAt;
        final bDate = b.lastConnectedAt ?? b.createdAt;
        final byDate = bDate.compareTo(aDate);
        if (byDate != 0) return byDate;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    case ProfileSort.nameAZ:
      sorted.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    case ProfileSort.nameZA:
      sorted.sort(
        (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
      );
  }
  return sorted;
}
