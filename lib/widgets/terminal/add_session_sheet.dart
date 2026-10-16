import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../models/session_tab.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/groups_provider.dart';
import '../../providers/ssh_session_manager_provider.dart';
import '../../screens/search/global_search_launcher.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/ssh/ssh_session_manager.dart';
import '../../services/storage/group_storage.dart';
import '../../theme/theme.dart';
import '../../utils/group_match.dart';
import '../../utils/profile_sort.dart';
import '../groups/group_filter_chips.dart';
import '../profiles/profile_avatar.dart';
import '../ui/app_card.dart';
import '../ui/app_dropdown.dart';
import '../ui/app_notifications.dart';
import '../ui/confirm_dialog.dart';
import '../ui/sheet_handle.dart';
import 'new_session_row.dart';
import 'rename_session_dialog.dart';

/// Where a tab comes from: a machine to open a fresh shell on, or one of the
/// sessions already waiting on it.
///
/// The tab bar carries connected sessions only, so a session the user detached
/// has nowhere else to be picked up from - offering the machine without its
/// waiting sessions would mean starting a second shell next to the one they
/// meant to come back to.
class AddSessionSheetContent extends ConsumerStatefulWidget {
  const AddSessionSheetContent({
    super.key,
    required this.profiles,
    required this.resumableFor,
    required this.onSelect,
    required this.onAttach,
  });

  final List<SshProfile> profiles;

  /// Sessions still running on [profileId] with nothing attached to them.
  final List<SessionTab> Function(String profileId) resumableFor;

  /// Start a new session on this machine.
  final ValueChanged<SshProfile> onSelect;

  /// Pick up the session bound to this tab id.
  final void Function(String tabId, SshProfile profile) onAttach;

  @override
  ConsumerState<AddSessionSheetContent> createState() =>
      _AddSessionSheetContentState();
}

/// Typing in the search launcher happens full screen, over machines only;
/// a pick there is the same as tapping the machine here.
class _AddSessionSheetContentState
    extends ConsumerState<AddSessionSheetContent> {
  String _selectedGroup = '';

  List<SshProfile> _filterProfiles(
    List<SshProfile> profiles,
    Set<String> knownGroups,
  ) {
    final filtered = profiles.where((p) {
      final effectiveGroup = knownGroups.contains(p.group)
          ? p.group
          : GroupStorage.defaultGroup;
      return _selectedGroup.isEmpty || effectiveGroup == _selectedGroup;
    }).toList();

    return sortProfiles(filtered);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final anonymize = ref.watch(anonymizeProvider);
    final profileGroups = ref.watch(profileGroupsProvider);
    final knownGroups = {for (final g in profileGroups) g.name};
    String effectiveGroup(SshProfile p) =>
        knownGroups.contains(p.group) ? p.group : GroupStorage.defaultGroup;

    final groupNames = widget.profiles.map(effectiveGroup).toSet().toList();
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
    final filtered = _filterProfiles(widget.profiles, knownGroups);

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
              const SheetHandle(topPadding: AppTheme.space8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space20,
                  vertical: AppTheme.space14,
                ),
                child: Text(
                  t.terminal.selectDevice,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space16,
                ),
                child: GlobalSearchLauncher(
                  heroTag: 'globalSearch-addSession',
                  hint: t.terminal.searchDevices,
                  pickFrom: widget.profiles,
                  onPick: widget.onSelect,
                ),
              ),
              GroupFilterChips(
                groups: allGroups,
                selected: _selectedGroup,
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space16,
                  AppTheme.space10,
                  AppTheme.space16,
                  0,
                ),
                onChanged: (group) => setState(() => _selectedGroup = group),
              ),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.space24,
                    horizontal: AppTheme.space20,
                  ),
                  child: Text(
                    t.terminal.noDevices,
                    style: TextStyle(color: context.colors.textTertiary),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    key: const ValueKey('addSessionProfileList'),
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.space16,
                      AppTheme.space12,
                      AppTheme.space16,
                      AppTheme.space16,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppTheme.space12),
                    itemBuilder: (context, index) {
                      final p = filtered[index];
                      return _ProfileRow(
                        key: ValueKey('addSessionProfile:${p.id}'),
                        profile: p,
                        anonymize: anonymize,
                        resumable: widget.resumableFor(p.id),
                        onSelect: () => widget.onSelect(p),
                        onAttachTab: (tabId) => widget.onAttach(tabId, p),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

enum _RemoteSessionAction { attach, rename, kill }

/// A machine, the sessions this device already knows are waiting on it, and -
/// on demand, behind the row's own menu - whatever the server itself reports.
/// Listing costs an SSH round trip, so it never happens until asked for.
class _ProfileRow extends ConsumerStatefulWidget {
  const _ProfileRow({
    super.key,
    required this.profile,
    required this.anonymize,
    required this.resumable,
    required this.onSelect,
    required this.onAttachTab,
  });

  final SshProfile profile;
  final bool anonymize;
  final List<SessionTab> resumable;
  final VoidCallback onSelect;
  final ValueChanged<String> onAttachTab;

  @override
  ConsumerState<_ProfileRow> createState() => _ProfileRowState();
}

/// The new-session row is always last, same as the home screen's own
/// new-session row - a dedicated way to start a fresh session without
/// repurposing a tap on the card or on one of the rows above it.
class _ProfileRowState extends ConsumerState<_ProfileRow> {
  late final SshSessionManager _manager = ref.read(sshSessionManagerProvider);

  List<RemoteMuxSession>? _remote;
  bool _loading = false;
  String? _error;

  Future<void> _loadRemote() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await _manager.listRemoteSessions(widget.profile);
      if (!mounted) return;
      setState(() {
        _remote = sessions;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _attachRemote(RemoteMuxSession session) {
    final tabId = _manager.adoptRemoteSession(
      widget.profile,
      session.name,
      multiplexer: session.multiplexer,
    );
    widget.onAttachTab(tabId);
  }

  Future<void> _renameRemote(RemoteMuxSession session) async {
    await showRenameSessionDialog(
      context,
      currentName: session.name,
      onRename: (newName) => _manager.renameRemoteSession(
        widget.profile,
        session.name,
        newName,
        multiplexer: session.multiplexer,
      ),
    );
    if (mounted) await _loadRemote();
  }

  Future<void> _killRemote(RemoteMuxSession session) async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.session.killSessionTitle,
      message: t.session.killSessionConfirm(
        name: SessionTab.displayName(session.name),
      ),
      confirmLabel: t.session.kill,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    try {
      await _manager.killRemoteSession(
        widget.profile,
        session.name,
        multiplexer: session.multiplexer,
      );
      if (mounted) {
        AppNotifications.success(
          context,
          t.session.killed(name: SessionTab.displayName(session.name)),
        );
      }
    } catch (error) {
      if (mounted) {
        AppNotifications.error(
          context,
          t.session.serverSessionsFailed(
            error: error.toString().replaceFirst('Exception: ', ''),
          ),
        );
      }
    }
    if (mounted) await _loadRemote();
  }

  /// Sessions the server reported that this device has no waiting tab for -
  /// the ones already listed above would otherwise appear twice. Attached
  /// sessions are someone else's live shell right now, not something to
  /// pick up here, so only the detached ones ever surface.
  List<RemoteMuxSession> get _unlistedRemote {
    final known = widget.resumable.map((tab) => tab.muxName).toSet();
    return (_remote ?? const <RemoteMuxSession>[])
        .where((session) => !session.attached && !known.contains(session.name))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final profile = widget.profile;
    final belowBuilders = <Widget Function(bool isLast)>[];

    for (final tab in widget.resumable) {
      belowBuilders.add(
        (isLast) => _ResumableSessionRow(
          key: ValueKey('addSessionResume:${tab.tabId}'),
          tab: tab,
          isLast: isLast,
          onTap: () => widget.onAttachTab(tab.tabId),
        ),
      );
    }

    if (_loading) {
      belowBuilders.add(
        (isLast) => _StatusRow(
          isLast: isLast,
          color: context.colors.textTertiary,
          text: t.session.loadingServerSessions,
        ),
      );
    } else if (_error != null) {
      belowBuilders.add(
        (isLast) => _StatusRow(
          isLast: isLast,
          color: context.colors.error,
          text: t.session.serverSessionsFailed(error: _error!),
        ),
      );
    } else if (_remote != null && _unlistedRemote.isEmpty) {
      belowBuilders.add(
        (isLast) => _StatusRow(
          isLast: isLast,
          color: context.colors.textTertiary,
          text: t.session.noServerSessions,
        ),
      );
    }

    for (final session in _unlistedRemote) {
      belowBuilders.add(
        (isLast) => _RemoteSessionRow(
          key: ValueKey('addSessionRemote:${profile.id}:${session.name}'),
          session: session,
          isLast: isLast,
          onSelected: (action) {
            switch (action) {
              case _RemoteSessionAction.attach:
                _attachRemote(session);
              case _RemoteSessionAction.rename:
                unawaited(_renameRemote(session));
              case _RemoteSessionAction.kill:
                unawaited(_killRemote(session));
            }
          },
          onTap: () => _attachRemote(session),
        ),
      );
    }

    belowBuilders.add((isLast) => NewSessionRow(onTap: widget.onSelect));

    final belowWidgets = [
      for (var i = 0; i < belowBuilders.length; i++)
        belowBuilders[i](i == belowBuilders.length - 1),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMainRow(context, belowWidgets.isNotEmpty),
        ...belowWidgets,
      ],
    );
  }

  /// Mirrors `ProfileCard`'s card chrome: same avatar size, title/subtitle
  /// styles and `attachedBelow` corner logic, so a picked device reads as
  /// the same object whether it is being managed on the home screen or
  /// picked here.
  Widget _buildMainRow(BuildContext context, bool hasBelow) {
    final t = Translations.of(context);
    final profile = widget.profile;
    return AppCard.segment(
      first: true,
      last: !hasBelow,
      onTap: widget.onSelect,
      padding: const EdgeInsets.all(AppTheme.space14),
      child: Row(
        children: [
          ProfileAvatar(
            iconName: profile.iconName,
            colorHex: profile.colorHex,
            size: 42,
          ),
          const SizedBox(width: AppTheme.space14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.anonymize
                      ? IdentityAnonymizer.name(profile.id)
                      : profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.colors.itemTitle,
                ),
                const SizedBox(height: AppTheme.space4),
                Text(
                  widget.anonymize
                      ? '${IdentityAnonymizer.username(profile.id)}@${IdentityAnonymizer.host(profile.id)}:${profile.port}'
                      : '${profile.username}@${profile.host}:${profile.port}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.colors.uiStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space8),
          SizedBox(
            width: AppTheme.icon40,
            height: AppTheme.icon40,
            child: IconButton(
              key: ValueKey('addSessionMore:${profile.id}'),
              tooltip: t.common.refresh,
              iconSize: AppTheme.icon20,
              padding: EdgeInsets.zero,
              color: context.colors.textTertiary,
              icon: _loading
                  ? const SizedBox(
                      width: AppTheme.icon16,
                      height: AppTheme.icon16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsRegular.arrowClockwise),
              onPressed: _loading ? null : _loadRemote,
            ),
          ),
        ],
      ),
    );
  }
}

/// A stitched-under status line (loading / error / empty) between the main
/// row and whatever follows it - same box chrome as the session rows around
/// it, just text instead of a tappable target.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.text,
    required this.color,
    required this.isLast,
  });

  final String text;
  final Color color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return AppCard.segment(
      first: false,
      last: isLast,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space16 + AppTheme.icon8 + AppTheme.space12,
        AppTheme.space8,
        AppTheme.space16,
        AppTheme.space12,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppTheme.font12, color: color),
      ),
    );
  }
}

/// A session the server reported, with the actions that only make sense for
/// one that is not already waiting in a tab. Same box-and-dot chrome as
/// `_SessionRow` on the home screen - only the group's last row closes the
/// stitched card off.
/// Every session that reaches this row is already known to be detached -
/// see `_unlistedRemote` - so the dot always reads the same as a resumable
/// row's.
class _RemoteSessionRow extends StatelessWidget {
  const _RemoteSessionRow({
    super.key,
    required this.session,
    required this.isLast,
    required this.onSelected,
    required this.onTap,
  });

  final RemoteMuxSession session;
  final bool isLast;
  final ValueChanged<_RemoteSessionAction> onSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return AppCard.segment(
      first: false,
      last: isLast,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space16,
        AppTheme.space10,
        AppTheme.space8,
        AppTheme.space10,
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsRegular.circle,
            size: AppTheme.icon8,
            color: context.colors.warning,
          ),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Text(
              SessionTab.displayName(session.name),
              overflow: TextOverflow.ellipsis,
              style: context.colors.uiStyle.copyWith(fontSize: AppTheme.font13),
            ),
          ),
          AppActionDropdown<_RemoteSessionAction>(
            iconSize: AppTheme.icon16,
            width: 220,
            items: [
              DropdownItem(
                value: _RemoteSessionAction.attach,
                intrinsicHeight: true,
                child: AppDropdownItem(
                  icon: PhosphorIconsRegular.arrowUUpLeft,
                  label: t.session.attach,
                ),
              ),
              DropdownItem(
                value: _RemoteSessionAction.rename,
                intrinsicHeight: true,
                child: AppDropdownItem(
                  icon: PhosphorIconsRegular.pencilSimple,
                  label: t.session.rename,
                ),
              ),
              DropdownItem(
                value: _RemoteSessionAction.kill,
                intrinsicHeight: true,
                child: AppDropdownItem(
                  icon: PhosphorIconsRegular.trash,
                  label: t.session.kill,
                  color: context.colors.error,
                ),
              ),
            ],
            onSelected: onSelected,
          ),
        ],
      ),
    );
  }
}

/// One session still running on a machine with nothing attached to it.
class _ResumableSessionRow extends StatelessWidget {
  const _ResumableSessionRow({
    super.key,
    required this.tab,
    required this.isLast,
    required this.onTap,
  });

  final SessionTab tab;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return AppCard.segment(
      first: false,
      last: isLast,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space16,
        AppTheme.space10,
        AppTheme.space8,
        AppTheme.space10,
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsRegular.circle,
            size: AppTheme.icon8,
            color: context.colors.warning,
          ),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Text(
              SessionTab.displayName(tab.muxName),
              overflow: TextOverflow.ellipsis,
              style: context.colors.uiStyle.copyWith(fontSize: AppTheme.font13),
            ),
          ),
          const SizedBox(width: AppTheme.space8),
          Text(
            t.session.attach,
            style: TextStyle(
              fontSize: AppTheme.font12,
              fontWeight: FontWeight.w600,
              color: context.colors.warning,
            ),
          ),
          const SizedBox(width: AppTheme.space6),
          Icon(
            PhosphorIconsFill.caretRight,
            size: AppTheme.icon16,
            color: context.colors.textTertiary,
          ),
        ],
      ),
    );
  }
}
