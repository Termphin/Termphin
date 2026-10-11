import '../../models/active_session.dart';
import '../../models/profile_group.dart';
import '../../models/session_tab.dart';
import '../../models/snippet.dart';
import '../../models/ssh_key.dart';
import '../../models/ssh_profile.dart';
import '../../utils/group_match.dart';
import '../../utils/profile_sort.dart';
import '../storage/group_storage.dart';

/// A group as a search result, with what it holds so the row can say so.
class GroupHit {
  const GroupHit({
    required this.group,
    required this.machines,
    required this.snippets,
    required this.keys,
  });

  final ProfileGroup group;
  final int machines;
  final int snippets;
  final int keys;
}

/// The sections of a result list, in the order they are drawn when nothing
/// ranks them: open sessions over the machines they run on.
enum SearchSection { sessions, machines, groups, snippets, keys }

class GlobalSearchResults {
  const GlobalSearchResults({
    this.machines = const [],
    this.sessions = const [],
    this.groups = const [],
    this.snippets = const [],
    this.keys = const [],
    this.sections = SearchSection.values,
  });

  final List<SshProfile> machines;
  final List<ActiveSessionView> sessions;
  final List<GroupHit> groups;
  final List<Snippet> snippets;
  final List<SshKey> keys;

  /// Every section, the one holding the best match first. Empty ones are
  /// still listed; the screen skips them.
  final List<SearchSection> sections;

  List<Object> itemsOf(SearchSection section) => switch (section) {
    SearchSection.sessions => sessions,
    SearchSection.machines => machines,
    SearchSection.groups => groups,
    SearchSection.snippets => snippets,
    SearchSection.keys => keys,
  };

  /// The best match of all, what Enter takes.
  Object? get top {
    for (final section in sections) {
      final items = itemsOf(section);
      if (items.isNotEmpty) return items.first;
    }
    return null;
  }

  bool get isEmpty =>
      machines.isEmpty &&
      sessions.isEmpty &&
      groups.isEmpty &&
      snippets.isEmpty &&
      keys.isEmpty;
}

/// How much a match in each field counts. A word in an item's own name is
/// what it is called; the same word in its group only says where it is
/// filed, so "main" puts the key named main above every machine in a group
/// called main.
abstract final class SearchWeights {
  static const name = 1.0;
  static const host = 0.8;
  static const userAtHost = 0.8;
  static const username = 0.55;
  static const command = 0.5;
  static const keyType = 0.5;
  static const group = 0.35;

  /// A session found through its machine ranks just under that machine.
  static const viaMachine = 0.9;

  /// Per kind, to break near-ties: something to connect to before something
  /// to look at.
  static const kind = {
    SearchSection.sessions: 1.0,
    SearchSection.machines: 1.0,
    SearchSection.groups: 0.95,
    SearchSection.snippets: 0.9,
    SearchSection.keys: 0.9,
  };
}

/// How well one typed word fits one field, from 1 (the field is the word)
/// down to 0 (not in it).
double matchQuality(String term, String field) {
  final text = field.toLowerCase();
  if (text.isEmpty) return 0;
  if (text == term) return 1;
  if (text.startsWith(term)) return 0.8;
  var best = 0.0;
  var from = 0;
  while (true) {
    final at = text.indexOf(term, from);
    if (at < 0) break;
    final end = at + term.length;
    final startsWord = at == 0 || !_isWordChar(text.codeUnitAt(at - 1));
    final endsWord = end == text.length || !_isWordChar(text.codeUnitAt(end));
    final q = startsWord ? (endsWord ? 0.7 : 0.6) : 0.3;
    if (q > best) best = q;
    from = at + 1;
  }
  return best;
}

/// Whether [c] is a digit, a lowercased ASCII letter, or anything outside
/// ASCII - which is treated as a letter too, so "ó" does not split a word.
bool _isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7a) || c > 0x7f;

/// Every word has to fit some field; the score is the average of each
/// word's best fit, scaled by the field's weight. 0 is no match.
double _score(List<String> terms, List<(String, double)> fields) {
  var total = 0.0;
  for (final term in terms) {
    var best = 0.0;
    for (final (text, weight) in fields) {
      final s = matchQuality(term, text) * weight;
      if (s > best) best = s;
    }
    if (best == 0) return 0;
    total += best;
  }
  return total / terms.length;
}

/// Everything the search box can find, matched and ranked in one place so
/// the screen only draws.
///
/// Every word of the query has to appear somewhere in an item - "prod root"
/// finds root on a production machine, not everything with either word.
/// Items are ranked by [SearchWeights], and so are the sections: whichever
/// holds the best match comes first. A record whose group is not a known one
/// counts as the default group, the same way the lists place it.
/// [generalLabel] is the default group's localized name, so "Ogólne" finds
/// it as well as "General". [scope] narrows every section to one group; the
/// groups section is then empty.
///
/// With nothing typed and no scope there is nothing to match: the screen
/// shows the most recently used machines and the sessions that are open.
///
/// Sections tie-break on their usual order ([SearchSection]'s own index),
/// so equal scores do not shuffle them around.
GlobalSearchResults globalSearch({
  required String query,
  required List<SshProfile> profiles,
  required List<ProfileGroup> groups,
  required List<ActiveSessionView> sessions,
  required List<Snippet> snippets,
  required List<SshKey> keys,
  required String generalLabel,
  String? scope,
  int recentLimit = 5,
}) {
  final terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
  final knownGroups = [
    for (final g in groups) g.name,
    if (!groups.any((g) => isSameGroup(g.name, GroupStorage.defaultGroup)))
      GroupStorage.defaultGroup,
  ];
  String groupOf(String recordGroup) =>
      resolveGroupName(recordGroup, knownGroups) ?? GroupStorage.defaultGroup;
  List<(String, double)> groupFields(String group, double weight) => [
    (group, weight),
    if (isSameGroup(group, GroupStorage.defaultGroup)) (generalLabel, weight),
  ];
  bool inScope(String recordGroup) =>
      scope == null || isSameGroup(groupOf(recordGroup), scope);

  final tabs = sessions.where((s) => !s.isRun).toList();

  if (terms.isEmpty && scope == null) {
    return GlobalSearchResults(
      machines: sortProfiles(profiles).take(recentLimit).toList(),
      sessions: tabs.where((s) => !s.dropped).toList(),
    );
  }

  List<(String, double)> profileFields(SshProfile p, [double scale = 1]) => [
    (p.name, SearchWeights.name * scale),
    (p.host, SearchWeights.host * scale),
    (p.username, SearchWeights.username * scale),
    ('${p.username}@${p.host}', SearchWeights.userAtHost * scale),
    ...groupFields(groupOf(p.group), SearchWeights.group * scale),
  ];
  String muxName(ActiveSessionView s) =>
      s.muxName == null ? '' : SessionTab.displayName(s.muxName!);

  final machines = _rank(
    sortProfiles(profiles).where((p) => inScope(p.group)),
    terms,
    profileFields,
  );

  final sessionHits = _rank(
    tabs.where((s) => inScope(s.profile.group)),
    terms,
    (s) => [
      (muxName(s), SearchWeights.name),
      ...profileFields(s.profile, SearchWeights.viaMachine),
    ],
  );

  final groupHits = scope != null || terms.isEmpty
      ? const <(GroupHit, double)>[]
      : _rank(groups, terms, (g) => groupFields(g.name, SearchWeights.name))
            .map(
              (hit) => (
                GroupHit(
                  group: hit.$1,
                  machines: profiles
                      .where((p) => isSameGroup(groupOf(p.group), hit.$1.name))
                      .length,
                  snippets: snippets
                      .where((s) => isSameGroup(groupOf(s.group), hit.$1.name))
                      .length,
                  keys: keys
                      .where((k) => isSameGroup(groupOf(k.group), hit.$1.name))
                      .length,
                ),
                hit.$2,
              ),
            )
            .toList();

  final snippetHits = _rank(
    snippets.where((s) => inScope(s.group)),
    terms,
    (s) => [
      (s.name, SearchWeights.name),
      (s.command, SearchWeights.command),
      ...groupFields(groupOf(s.group), SearchWeights.group),
    ],
  );

  final keyHits = _rank(
    keys.where((k) => inScope(k.group)),
    terms,
    (k) => [
      (k.name, SearchWeights.name),
      (k.keyType.label, SearchWeights.keyType),
      ...groupFields(groupOf(k.group), SearchWeights.group),
    ],
  );

  double best(SearchSection section, List<(Object?, double)> hits) =>
      hits.isEmpty ? 0 : hits.first.$2 * SearchWeights.kind[section]!;
  final bestOf = {
    SearchSection.sessions: best(SearchSection.sessions, sessionHits),
    SearchSection.machines: best(SearchSection.machines, machines),
    SearchSection.groups: best(SearchSection.groups, groupHits),
    SearchSection.snippets: best(SearchSection.snippets, snippetHits),
    SearchSection.keys: best(SearchSection.keys, keyHits),
  };
  final sections = [...SearchSection.values]
    ..sort((a, b) {
      final byScore = bestOf[b]!.compareTo(bestOf[a]!);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });

  List<T> items<T>(List<(T, double)> hits) => [for (final (i, _) in hits) i];
  return GlobalSearchResults(
    machines: items(machines),
    sessions: items(sessionHits),
    groups: items(groupHits),
    snippets: items(snippetHits),
    keys: items(keyHits),
    sections: sections,
  );
}

/// The items that match, best first, each with its score; equal scores keep
/// the order they came in. With nothing typed everything matches equally.
List<(T, double)> _rank<T>(
  Iterable<T> items,
  List<String> terms,
  List<(String, double)> Function(T) fields,
) {
  final scored =
      [
        for (final (i, item) in items.indexed)
          if ((terms.isEmpty ? 1.0 : _score(terms, fields(item))) case final s
              when s > 0)
            (i, item, s),
      ]..sort((a, b) {
        final byScore = b.$3.compareTo(a.$3);
        return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
      });
  return [for (final (_, item, s) in scored) (item, s)];
}
