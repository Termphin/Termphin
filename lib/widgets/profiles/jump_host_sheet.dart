import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/groups_provider.dart';
import '../../screens/search/global_search_launcher.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/storage/group_storage.dart';
import '../../theme/theme.dart';
import '../../utils/group_match.dart';
import '../../utils/profile_sort.dart';
import '../ui/group_filter_chips.dart';
import '../ui/section_header.dart';
import '../ui/sheet_handle.dart';
import 'profile_avatar.dart';

/// Picks the profile a connection hops through, or none at all.
///
/// Built like the sheet that opens a new session - same search, group chips
/// and machine cards - so a machine reads as the same object in both, minus
/// the sessions: a jump host is only ever a machine. Profiles in [group] come
/// first, since a jump host usually sits next to what it guards.
class JumpHostSheetContent extends ConsumerStatefulWidget {
  const JumpHostSheetContent({
    super.key,
    required this.candidates,
    required this.group,
    required this.selectedId,
    required this.onPick,
  });

  final List<SshProfile> candidates;

  /// The group of the profile being edited.
  final String group;
  final String? selectedId;

  /// Called with the picked profile's id, or null for a direct connection.
  final ValueChanged<String?> onPick;

  @override
  ConsumerState<JumpHostSheetContent> createState() =>
      _JumpHostSheetContentState();
}

class _JumpHostSheetContentState extends ConsumerState<JumpHostSheetContent> {
  String _selectedGroup = '';

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final anonymize = ref.watch(anonymizeProvider);
    final profileGroups = ref.watch(profileGroupsProvider);
    final knownGroups = {for (final g in profileGroups) g.name};
    String effectiveGroup(SshProfile p) =>
        knownGroups.contains(p.group) ? p.group : GroupStorage.defaultGroup;

    final groupNames = widget.candidates.map(effectiveGroup).toSet().toList();
    groupNames.sort((a, b) {
      if (a == GroupStorage.defaultGroup) return -1;
      if (b == GroupStorage.defaultGroup) return 1;
      return a.compareTo(b);
    });
    final allGroups = [
      for (final name in groupNames)
        profileGroups.where((g) => isSameGroup(g.name, name)).firstOrNull ??
            ProfileGroup(name: name),
    ];

    final visible = sortProfiles([
      for (final p in widget.candidates)
        if (_selectedGroup.isEmpty || effectiveGroup(p) == _selectedGroup) p,
    ]);
    final sameGroup = [
      for (final p in visible)
        if (isSameGroup(p.group, widget.group)) p,
    ];
    final otherGroups = [
      for (final p in visible)
        if (!isSameGroup(p.group, widget.group)) p,
    ];

    Widget row(SshProfile p) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _MachineRow(
        key: ValueKey('jumpHostCandidate:${p.id}'),
        profile: p,
        anonymize: anonymize,
        selected: p.id == widget.selectedId,
        onTap: () => widget.onPick(p.id),
      ),
    );

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(topPadding: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Text(
                  t.profileForm.jumpHost,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GlobalSearchLauncher(
                  heroTag: 'globalSearch-jumpHost',
                  hint: t.terminal.searchDevices,
                  pickFrom: widget.candidates,
                  onPick: (p) => widget.onPick(p.id),
                ),
              ),
              GroupFilterChips(
                groups: allGroups,
                selected: _selectedGroup,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                onChanged: (group) => setState(() => _selectedGroup = group),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('jumpHostList'),
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _DirectRow(
                        selected: widget.selectedId == null,
                        onTap: () => widget.onPick(null),
                      ),
                    ),
                    for (final p in sameGroup) row(p),
                    if (sameGroup.isNotEmpty && otherGroups.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                        child: SectionHeader(t.groups.otherGroups),
                      ),
                    for (final p in otherGroups) row(p),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The card chrome shared by both rows, matching the new-session sheet's
/// machine card, with a check on the current choice.
class _PickCard extends StatelessWidget {
  const _PickCard({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Material(
      color: context.colors.surfaceElevated.invisible,
      borderRadius: radius,
      child: Ink(
        decoration: BoxDecoration(
          color: context.colors.surfaceElevated,
          borderRadius: radius,
          border: Border.all(
            color: selected
                ? context.colors.primary
                : context.colors.surfaceBorder,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.colors.itemTitle,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.colors.uiStyle,
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(
                    PhosphorIconsRegular.checkCircle,
                    size: 20,
                    color: context.colors.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectRow extends StatelessWidget {
  const _DirectRow({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return _PickCard(
      key: const ValueKey('jumpHostDirect'),
      leading: SizedBox(
        width: 42,
        height: 42,
        child: Icon(
          PhosphorIconsRegular.arrowRight,
          color: context.colors.textSecondary,
        ),
      ),
      title: t.profileForm.jumpHostNone,
      subtitle: null,
      selected: selected,
      onTap: onTap,
    );
  }
}

class _MachineRow extends StatelessWidget {
  const _MachineRow({
    super.key,
    required this.profile,
    required this.anonymize,
    required this.selected,
    required this.onTap,
  });

  final SshProfile profile;
  final bool anonymize;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PickCard(
      leading: ProfileAvatar(
        iconName: profile.iconName,
        colorHex: profile.colorHex,
        size: 42,
      ),
      title: anonymize ? IdentityAnonymizer.name(profile.id) : profile.name,
      subtitle: jumpHostAddress(profile, anonymize: anonymize),
      selected: selected,
      onTap: onTap,
    );
  }
}

/// `user@host:port` for [profile], with the anonymized identity when
/// [anonymize] is on.
String jumpHostAddress(SshProfile profile, {required bool anonymize}) =>
    anonymize
    ? '${IdentityAnonymizer.username(profile.id)}@${IdentityAnonymizer.host(profile.id)}:${profile.port}'
    : '${profile.username}@${profile.host}:${profile.port}';
