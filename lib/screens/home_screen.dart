import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../i18n/strings.g.dart';
import '../models/active_session.dart';
import '../models/profile_group.dart';
import '../models/ssh_profile.dart';
import '../providers/anonymize_provider.dart';
import '../providers/groups_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/ssh_connection_provider.dart';
import '../providers/ssh_session_manager_provider.dart';
import '../providers/terminal_overlay_provider.dart';
import '../services/app/app_commands.dart';
import '../services/app/identity_anonymizer.dart';
import '../services/sftp/cancel_token.dart';
import '../services/ssh/ssh_link.dart';
import '../services/ssh/ssh_session_manager.dart';
import '../services/storage/group_storage.dart';
import '../theme/theme.dart';
import '../utils/group_match.dart';
import '../utils/profile_sort.dart';
import '../widgets/profiles/profile_card.dart';
import '../widgets/profiles/profile_form_dialog.dart';
import '../widgets/profiles/profile_search_field.dart';
import '../widgets/profiles/server_guide.dart';
import '../widgets/ssh/session_status.dart';
import '../widgets/terminal/rename_session_dialog.dart';
import '../widgets/ui/app_dropdown.dart';
import '../widgets/ui/app_form_field.dart';
import '../widgets/ui/app_notifications.dart';
import '../widgets/ui/app_sheet.dart';
import '../widgets/ui/confirm_dialog.dart';
import '../widgets/ui/context_menu.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/group_filter_chips.dart';
import '../widgets/ui/group_picker_sheet.dart';
import '../widgets/ui/group_section_header.dart';
import '../widgets/ui/large_title_scaffold.dart';
import '../widgets/ui/selection_action_bar.dart';
import 'search/global_search_launcher.dart';

const _uuid = Uuid();

/// One group header's load in flight: the machines it has dialled, and the
/// switch that stops the lot.
class _GroupSessionLoad {
  final CancelToken _cancel = CancelToken();
  final Set<String> machineIds = {};

  bool get isCancelled => _cancel.isCancelled;

  void cancel() => _cancel.cancel();
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// A group with nothing to show here draws no section: an empty header
/// would cost as much room as a real one while saying only that it is
/// empty - the group is still on the groups screen, and the form's picker
/// still offers it. The group filter chips, though, only list groups that
/// have a machine, since a chip leading to a certain empty list is a dead
/// end. A section header counts what it currently loads: the machines on
/// screen, not the ones a search is currently hiding.
class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final SshSessionManager _manager = ref.read(sshSessionManagerProvider);

  final Set<String> _selectedProfileIds = {};
  final Map<String, CancelToken> _loadingRemoteSessions = {};
  final Map<String, _GroupSessionLoad> _loadingRemoteSessionGroups = {};
  final Map<String, DateTime> _remoteSessionsCheckedAt = {};
  String _selectedGroup = '';
  ProfileSort _selectedSort = ProfileSort.recentlyUsed;
  final _sortNotifier = ValueNotifier<ProfileSort>(ProfileSort.recentlyUsed);

  late final VoidCallback _unregisterEscape;

  /// Esc on a desktop drops the selection, as a click on its X does.
  bool _clearSelectionOnEscape() {
    if (!mounted || _selectedProfileIds.isEmpty) return false;
    setState(() => _selectedProfileIds.clear());
    return true;
  }

  @override
  void initState() {
    super.initState();
    _unregisterEscape = AppCommands.instance.registerEscape(
      _clearSelectionOnEscape,
    );
  }

  @override
  void dispose() {
    _unregisterEscape();
    _sortNotifier.dispose();
    super.dispose();
  }

  Future<void> _showProfileDialog({
    SshProfile? profile,
    String? initialGroup,
    SshLink? prefill,
  }) {
    return pushAppForm<void>(
      context,
      builder: (_) => ProfileFormDialog(
        profile: profile,
        initialGroup: initialGroup,
        prefill: prefill,
      ),
    );
  }

  Future<void> _confirmDeleteProfile(SshProfile profile) async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.profiles.deleteTitle,
      message: t.profiles.deleteConfirm(name: profile.name),
      confirmLabel: t.common.delete,
      destructive: true,
    );
    if (!confirmed) return;
    if (!mounted) return;
    await ref.read(profilesProvider.notifier).deleteProfile(profile.id);
    if (!mounted) return;
    setState(() => _selectedProfileIds.remove(profile.id));
    AppNotifications.success(context, t.profiles.deleted);
  }

  Future<void> _moveSelectedProfiles() async {
    final allProfiles = ref.read(profilesProvider);
    final selectedProfiles = allProfiles
        .where((p) => _selectedProfileIds.contains(p.id))
        .toList();
    if (selectedProfiles.isEmpty) return;

    final groups = ref.read(profileGroupsProvider);
    final effectiveGroups = groups.isNotEmpty
        ? groups
        : const [ProfileGroup(name: GroupStorage.defaultGroup)];

    final firstGroup = selectedProfiles.first.group;
    final allSame = selectedProfiles.every(
      (p) => isSameGroup(p.group, firstGroup),
    );
    final current = allSame ? firstGroup : null;

    final chosenGroup = await showGroupPickerSheet(
      context,
      groups: effectiveGroups,
      current: current,
    );
    if (chosenGroup == null) return;
    if (!mounted) return;

    final count = selectedProfiles.length;
    for (final profile in selectedProfiles) {
      await ref
          .read(profilesProvider.notifier)
          .updateProfile(
            profile,
            name: profile.name,
            host: profile.host,
            port: profile.port,
            username: profile.username,
            authMethod: profile.authMethod,
            password: profile.password,
            privateKey: profile.privateKey,
            passphrase: profile.passphrase,
            sshKeyId: profile.sshKeyId,
            portForwardings: profile.portForwardings,
            group: chosenGroup,
            iconName: profile.iconName,
            colorHex: profile.colorHex,
            fallbackHosts: profile.fallbackHosts,
            jumpHostProfileId: profile.jumpHostProfileId,
          );
    }
    if (!mounted) return;
    setState(() => _selectedProfileIds.clear());

    final displayGroupName = isSameGroup(chosenGroup, GroupStorage.defaultGroup)
        ? Translations.of(context).groups.general
        : chosenGroup;
    AppNotifications.success(
      context,
      Translations.of(
        context,
      ).selection.moved(n: count, count: count, group: displayGroupName),
    );
  }

  Future<void> _deleteSelectedProfiles() async {
    final allProfiles = ref.read(profilesProvider);
    final count = _selectedProfileIds.length;
    if (count == 0) return;

    final dependents = allProfiles
        .where(
          (p) =>
              !_selectedProfileIds.contains(p.id) &&
              p.jumpHostProfileId != null &&
              _selectedProfileIds.contains(p.jumpHostProfileId),
        )
        .toList();

    final t = Translations.of(context);
    final String title;
    final String message;
    final String confirmLabel;

    if (dependents.isEmpty) {
      title = t.selection.deleteTitle(n: count, count: count);
      message = t.selection.deleteConfirm;
      confirmLabel = t.common.delete;
    } else {
      title = t.selection.inUseTitle;
      message = [
        t.selection.machinesInUseBody(
          n: dependents.length,
          count: dependents.length,
        ),
        ...dependents.map((p) => p.name),
        t.selection.deleteConfirm,
      ].join('\n');
      confirmLabel = t.selection.deleteAnyway;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: true,
    );

    if (!confirmed) return;
    if (!mounted) return;

    final toDelete = _selectedProfileIds.toList();
    for (final id in toDelete) {
      await ref.read(profilesProvider.notifier).deleteProfile(id);
    }
    if (!mounted) return;
    setState(() => _selectedProfileIds.clear());
    AppNotifications.success(
      context,
      Translations.of(context).selection.deleted(n: count, count: count),
    );
  }

  /// Fetches detached sessions from the server and adopts them as inline
  /// session rows beneath the profile card. Returns how many were adopted and
  /// throws when the machine cannot be reached - saying so is the caller's
  /// business, since a group run reports once for the whole section.
  ///
  /// The token it registers is what the card's stop button trips, and what a
  /// group cancel reaches for machine by machine. That token is only cleared
  /// at the end if it is still this run's: a stop followed by a fresh tap
  /// leaves the newer token in the map, and clearing it here would hide a
  /// load that is still going.
  Future<int> _fetchRemoteSessions(SshProfile profile) async {
    final cancel = CancelToken();
    setState(() => _loadingRemoteSessions[profile.id] = cancel);
    try {
      final sessions = await _manager.listRemoteSessions(
        profile,
        cancel: cancel,
      );
      var adopted = 0;
      for (final session in sessions) {
        _manager.adoptRemoteSession(
          profile,
          session.name,
          multiplexer: session.multiplexer,
        );
        adopted++;
      }
      if (mounted) {
        setState(() => _remoteSessionsCheckedAt[profile.id] = DateTime.now());
      }
      return adopted;
    } finally {
      if (_loadingRemoteSessions[profile.id] == cancel) {
        if (mounted) {
          setState(() => _loadingRemoteSessions.remove(profile.id));
        } else {
          _loadingRemoteSessions.remove(profile.id);
        }
      }
    }
  }

  /// Stops one machine's load. A group run carries on without it.
  void _cancelRemoteSessions(SshProfile profile) =>
      _loadingRemoteSessions[profile.id]?.cancel();

  /// Loads detached sessions for one machine and reports the outcome via a
  /// toast - except when the user stopped it themselves: they already know,
  /// so a toast saying so is one more thing to read for an outcome they
  /// chose.
  Future<void> _loadRemoteSessions(SshProfile profile) async {
    if (_loadingRemoteSessions.containsKey(profile.id)) return;
    try {
      final adopted = await _fetchRemoteSessions(profile);
      if (!mounted) return;
      final t = Translations.of(context);
      if (adopted > 0) {
        AppNotifications.success(
          context,
          t.session.loadedSessions(count: adopted),
        );
      } else {
        AppNotifications.info(context, t.session.noServerSessions);
      }
    } on TransferCancelled catch (_) {
    } catch (error) {
      if (!mounted) return;
      AppNotifications.error(
        context,
        Translations.of(context).session.serverSessionsFailed(
          error: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// How many machines of a group are dialled at once. The handshake is mostly
  /// waiting on the network, so one at a time throws that wait away - but each
  /// one also runs its key exchange on this isolate, and a group of twenty at
  /// once would stall the frame that draws their spinners. Prompts do not
  /// enter into it: `main.dart` queues those so only one is ever on screen.
  static const _groupLoadConcurrency = 4;

  /// Stops a whole section's load: the queue takes no further machine, and
  /// every machine this run has in flight is torn down. A machine the user
  /// started from its own card is untouched - the group never owned it.
  void _cancelGroupRemoteSessions(ProfileGroup group) {
    final run = _loadingRemoteSessionGroups[group.name];
    if (run == null) return;
    run.cancel();
    for (final id in run.machineIds) {
      _loadingRemoteSessions[id]?.cancel();
    }
  }

  /// The per-machine load run across a whole section, [_groupLoadConcurrency]
  /// at a time, skipping any machine already loading from its own card to
  /// avoid a double round trip. A cancelled dial counts as neither adopted
  /// nor failed, and a machine that cannot be reached is counted, not
  /// shouted about - the section reports once, at the end, still naming what
  /// did land since silence about already-adopted tabs would read as the
  /// stop having undone them.
  Future<void> _loadGroupRemoteSessions(
    ProfileGroup group,
    List<SshProfile> profiles,
  ) async {
    if (_loadingRemoteSessionGroups.containsKey(group.name)) return;
    final run = _GroupSessionLoad();
    setState(() => _loadingRemoteSessionGroups[group.name] = run);
    final pending = profiles
        .where((p) => !_loadingRemoteSessions.containsKey(p.id))
        .toList();
    var adopted = 0;
    var failed = 0;
    try {
      var next = 0;
      Future<void> dialNext() async {
        while (mounted && !run.isCancelled) {
          final index = next++;
          if (index >= pending.length) return;
          final profile = pending[index];
          run.machineIds.add(profile.id);
          try {
            adopted += await _fetchRemoteSessions(profile);
          } on TransferCancelled catch (_) {
          } catch (_) {
            failed++;
          }
        }
      }

      await Future.wait([
        for (var i = 0; i < _groupLoadConcurrency && i < pending.length; i++)
          dialNext(),
      ]);
      if (!mounted) return;
    } finally {
      if (_loadingRemoteSessionGroups[group.name] == run) {
        if (mounted) {
          setState(() => _loadingRemoteSessionGroups.remove(group.name));
        } else {
          _loadingRemoteSessionGroups.remove(group.name);
        }
      }
    }

    if (!mounted) return;
    final t = Translations.of(context);
    if (run.isCancelled) {
      AppNotifications.info(context, t.session.loadStopped(count: adopted));
    } else if (adopted > 0 && failed > 0) {
      AppNotifications.info(
        context,
        t.session.loadedGroupSessionsPartial(count: adopted, failed: failed),
      );
    } else if (adopted > 0) {
      AppNotifications.success(
        context,
        t.session.loadedGroupSessions(
          count: adopted,
          machines: profiles.length,
        ),
      );
    } else if (failed > 0) {
      AppNotifications.error(
        context,
        t.session.groupSessionsFailed(failed: failed),
      );
    } else {
      AppNotifications.info(context, t.session.noGroupServerSessions);
    }
  }

  /// So a stale server-session list still on screen reads as stale, not as
  /// current fact.
  String? _sessionsCheckedLabel(String profileId) {
    final checkedAt = _remoteSessionsCheckedAt[profileId];
    if (checkedAt == null) return null;
    final t = Translations.of(context);
    final elapsed = DateTime.now().difference(checkedAt);
    if (elapsed.inMinutes < 1) return t.session.checkedJustNow;
    if (elapsed.inHours < 1) {
      return t.session.checkedMinutesAgo(minutes: elapsed.inMinutes);
    }
    if (elapsed.inDays < 1) {
      return t.session.checkedHoursAgo(hours: elapsed.inHours);
    }
    return t.session.checkedDaysAgo(days: elapsed.inDays);
  }

  void _openSession(
    String sessionId,
    SshProfile profile, {
    SiblingScope scope = SiblingScope.all,
  }) {
    ref
        .read(terminalOverlayProvider.notifier)
        .show(sessionId, profile, scope: scope);
  }

  /// Renames a session's mux name. Connected sessions reuse their live
  /// connection; detached ones go over a short one-shot connection.
  Future<void> _renameSessionRow(ActiveSessionView session) async {
    final currentName = session.muxName;
    if (currentName == null) return;
    final manager = _manager;
    await showRenameSessionDialog(
      context,
      currentName: currentName,
      onRename: (newName) async {
        if (!session.dropped) {
          return manager.renameSession(session.id, newName);
        }
        try {
          await manager.renameRemoteSession(
            session.profile,
            currentName,
            newName,
          );
        } catch (error) {
          if (mounted) unawaited(_offerForget(session, error));
          rethrow;
        }
      },
    );
  }

  /// A detached tab's rename goes over its own short-lived connection since
  /// there is no live transport to reuse - and on a server that lost the
  /// session entirely (rebuilt, agent state wiped by an outage, ...) that
  /// connection just fails every time, leaving the tab stuck with no way to
  /// act on it. This is the way out: drop it from
  /// the device without requiring the server to agree.
  Future<void> _offerForget(ActiveSessionView session, Object error) async {
    final t = Translations.of(context);
    final forget = await showConfirmDialog(
      context,
      title: t.session.unreachableTitle,
      message: t.session.unreachableBody(
        error: error.toString().replaceFirst('Exception: ', ''),
      ),
      confirmLabel: t.session.forget,
      destructive: true,
    );
    if (forget) {
      await _manager.forgetTab(session.id);
    }
  }

  /// Forgets the tab and kills its persistent session on the server. The row
  /// leaves at once; a failure to reach the server is reported afterwards,
  /// and the session it left running shows up among the server's own.
  ///
  /// A still-connected session ends through its own connection notifier, not
  /// the manager directly - a terminal opened earlier this run leaves that
  /// notifier's listener attached to the manager, and ending the session
  /// behind its back would make that listener see the drop and reconnect it,
  /// undoing the end.
  Future<void> _endSessionRow(ActiveSessionView session) async {
    final t = Translations.of(context);
    final host = ref.read(anonymizeProvider)
        ? IdentityAnonymizer.host(session.profile.id)
        : session.profile.host;
    final confirmed = await showConfirmDialog(
      context,
      title: t.session.endSessionTitle,
      message: t.session.endSessionConfirm(host: host),
      confirmLabel: t.session.endSession,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final notifyContext = AppNotifications.anchorOf(context);
    try {
      if (session.dropped) {
        final muxName = session.muxName;
        if (muxName == null) return;
        await _manager.killRemoteSession(session.profile, muxName);
      } else {
        await ref
            .read(sshConnectionProvider((session.id, session.profile)).notifier)
            .endSession();
      }
    } catch (error) {
      if (!notifyContext.mounted) return;
      AppNotifications.error(
        notifyContext,
        t.session.endSessionFailed(
          host: host,
          error: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// Detaches a connected session, leaving it running on the server.
  Future<void> _detachSessionRow(ActiveSessionView session) async {
    await ref
        .read(sshConnectionProvider((session.id, session.profile)).notifier)
        .disconnect();
  }

  List<SshProfile> _filteredProfiles(
    List<SshProfile> profiles,
    Set<String> knownGroups,
  ) {
    final result = profiles.where((p) {
      final effectiveGroup = knownGroups.contains(p.group)
          ? p.group
          : GroupStorage.defaultGroup;
      return _selectedGroup.isEmpty || effectiveGroup == _selectedGroup;
    }).toList();

    return sortProfiles(result, _selectedSort);
  }

  /// The machine's right-click menu on a desktop: what the card's tap, long
  /// press and `⋮` menu do, in one place under the pointer.
  List<ContextMenuEntry?> _profileMenu(SshProfile profile) {
    final t = Translations.of(context);
    final selected = _selectedProfileIds.contains(profile.id);
    return [
      ContextMenuEntry(
        label: t.contextMenu.connect,
        icon: PhosphorIconsRegular.terminalWindow,
        onSelected: () =>
            ref.read(terminalOverlayProvider.notifier).openProfile(profile),
      ),
      ContextMenuEntry(
        label: t.contextMenu.edit,
        icon: PhosphorIconsRegular.pencilSimple,
        onSelected: () => _showProfileDialog(profile: profile),
      ),
      ContextMenuEntry(
        label: t.session.loadSessions,
        icon: PhosphorIconsRegular.cloudArrowDown,
        enabled: !_loadingRemoteSessions.containsKey(profile.id),
        onSelected: () => unawaited(_loadRemoteSessions(profile)),
      ),
      ContextMenuEntry(
        label: t.contextMenu.select,
        icon: PhosphorIconsRegular.checkSquare,
        onSelected: () => setState(() {
          if (selected) {
            _selectedProfileIds.remove(profile.id);
          } else {
            _selectedProfileIds.add(profile.id);
          }
        }),
      ),
      null,
      ContextMenuEntry(
        label: t.contextMenu.delete,
        icon: PhosphorIconsRegular.trash,
        destructive: true,
        onSelected: () => unawaited(_confirmDeleteProfile(profile)),
      ),
    ];
  }

  /// One profile's card plus its attached session rows, kept together so
  /// related work stays grouped under its machine. The session rows ignore
  /// pointer events during multi-select, fading instead of disappearing, so
  /// nothing jumps under the finger while selection steps back from taking
  /// taps on them. A Ctrl-click on a desktop is the long press: it picks the
  /// card rather than opening it.
  Widget _buildProfileItem(SshProfile profile, SshSessionManager manager) {
    final tabs = manager.allTabsForProfile(profile.id);
    final liveTabs = tabs.where((s) => !s.dropped).toList();
    final selecting = _selectedProfileIds.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ContextMenuRegion(
            entries: () => _profileMenu(profile),
            child: ProfileCard(
              profile: profile,
              selected: _selectedProfileIds.contains(profile.id),
              selectionMode: selecting,
              onTap: () {
                if (_selectedProfileIds.isNotEmpty ||
                    selectionModifierPressed) {
                  setState(() {
                    if (_selectedProfileIds.contains(profile.id)) {
                      _selectedProfileIds.remove(profile.id);
                    } else {
                      _selectedProfileIds.add(profile.id);
                    }
                  });
                  return;
                }
                ref.read(terminalOverlayProvider.notifier).openProfile(profile);
              },
              onLongPress: () {
                setState(() {
                  _selectedProfileIds.add(profile.id);
                });
              },
              onEdit: () => _showProfileDialog(profile: profile),
              onLoadSessions: () => unawaited(_loadRemoteSessions(profile)),
              onCancelLoadSessions: () => _cancelRemoteSessions(profile),
              onDelete: () => unawaited(_confirmDeleteProfile(profile)),
              isLoadingSessions: _loadingRemoteSessions.containsKey(profile.id),
              sessionsCheckedLabel: _sessionsCheckedLabel(profile.id),
              isActive: liveTabs.isNotEmpty,
              attachedBelow: true,
            ),
          ),
          IgnorePointer(
            ignoring: selecting,
            child: AnimatedOpacity(
              opacity: selecting ? 0.4 : 1,
              duration: AppTheme.interactiveDuration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    _SessionRow(
                      session: tabs[i],
                      isLast: false,
                      onTap: () => _openSession(
                        tabs[i].id,
                        tabs[i].profile,
                        scope: SiblingScope.none,
                      ),
                      onRename: tabs[i].muxName == null
                          ? null
                          : () => _renameSessionRow(tabs[i]),
                      onDetach: tabs[i].dropped || tabs[i].muxName == null
                          ? null
                          : () => _detachSessionRow(tabs[i]),
                      onEnd: tabs[i].muxName == null
                          ? null
                          : () => _endSessionRow(tabs[i]),
                    ),
                  _NewSessionRow(
                    onTap: () => _openSession(
                      _uuid.v4(),
                      profile,
                      scope: SiblingScope.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider);
    final groups = ref.watch(profileGroupsProvider);
    final t = Translations.of(context);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: LargeTitleScaffold(
        resizeToAvoidBottomInset: false,
        title: t.profiles.machinesHeading,
        bodyBuilder: (context, scrollController, gutter) => ListenableBuilder(
          listenable: _manager,
          builder: (context, _) {
            final manager = _manager;
            final effectiveGroups = groups.isNotEmpty
                ? groups
                : const [ProfileGroup(name: GroupStorage.defaultGroup)];
            final knownGroups = {for (final g in effectiveGroups) g.name};
            String groupFor(SshProfile p) => knownGroups.contains(p.group)
                ? p.group
                : GroupStorage.defaultGroup;

            final visibleProfiles = _filteredProfiles(profiles, knownGroups);
            final populatedGroups = effectiveGroups
                .where((g) => profiles.any((p) => groupFor(p) == g.name))
                .toList();

            final displayGroups = effectiveGroups
                .where((g) => visibleProfiles.any((p) => groupFor(p) == g.name))
                .toList();
            final Map<ProfileGroup, List<SshProfile>> profilesByGroup = {
              for (final g in displayGroups)
                g: visibleProfiles.where((p) => groupFor(p) == g.name).toList(),
            };

            final allVisibleSelected =
                visibleProfiles.isNotEmpty &&
                visibleProfiles.every(
                  (p) => _selectedProfileIds.contains(p.id),
                );

            return SelectionActionHost(
              bar: _selectedProfileIds.isEmpty
                  ? null
                  : SelectionActionBar(
                      count: _selectedProfileIds.length,
                      onMove: _moveSelectedProfiles,
                      onDelete: _deleteSelectedProfiles,
                      onClear: () =>
                          setState(() => _selectedProfileIds.clear()),
                      onSelectAll: allVisibleSelected
                          ? null
                          : () => setState(
                              () => _selectedProfileIds.addAll(
                                visibleProfiles.map((p) => p.id),
                              ),
                            ),
                    ),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverPadding(
                    padding: gutter,
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverToBoxAdapter(
                          child: LargeTitleHeader(
                            title: Translations.of(
                              context,
                            ).profiles.machinesHeading,
                            subtitle: Translations.of(
                              context,
                            ).profiles.machinesSubtitle,
                          ),
                        ),
                        if (profiles.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            sliver: SliverToBoxAdapter(
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: GlobalSearchLauncher(
                                      heroTag: 'globalSearch-machines',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ProfileSortMenu(
                                    boxSize: kSearchBoxHeight,
                                    sort: _selectedSort,
                                    onChanged: (value) {
                                      setState(() => _selectedSort = value);
                                      _sortNotifier.value = value;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (profiles.isNotEmpty)
                          SliverToBoxAdapter(
                            child: GroupFilterChips(
                              groups: populatedGroups,
                              selected: _selectedGroup,
                              onChanged: (group) =>
                                  setState(() => _selectedGroup = group),
                            ),
                          ),
                        if (profiles.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _ProfilesEmptyState(
                              onAdd: () => _showProfileDialog(),
                              onQuickAdd: (link) =>
                                  _showProfileDialog(prefill: link),
                            ).animate().fadeIn(duration: 200.ms),
                          )
                        else ...[
                          for (final (i, group) in displayGroups.indexed) ...[
                            GroupSectionHeader.sliver(
                              group: group,
                              count:
                                  (profilesByGroup[group] ?? const []).length,
                              onAdd: () =>
                                  _showProfileDialog(initialGroup: group.name),
                              addTooltip: t.profiles.addMachineButton,
                              onLoadSessions: () => unawaited(
                                _loadGroupRemoteSessions(
                                  group,
                                  profilesByGroup[group] ?? const [],
                                ),
                              ),
                              onCancelLoadSessions: () =>
                                  _cancelGroupRemoteSessions(group),
                              isLoadingSessions: _loadingRemoteSessionGroups
                                  .containsKey(group.name),
                              padding: EdgeInsets.fromLTRB(
                                16,
                                i == 0 ? 4 : 16,
                                16,
                                4,
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.only(
                                top: 4,
                                bottom: 12,
                              ),
                              sliver: SliverList.separated(
                                itemCount:
                                    (profilesByGroup[group] ?? const []).length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) =>
                                    _buildProfileItem(
                                      (profilesByGroup[group] ??
                                          const [])[index],
                                      manager,
                                    ),
                              ),
                            ),
                          ],
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: _selectedProfileIds.isEmpty
                                  ? 32
                                  : SelectionActionBar.reservedHeight,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// No machines yet. The quickest way in is typing the machine the way one
/// would after `ssh` - it opens the form with host, port and user filled in.
class _ProfilesEmptyState extends StatefulWidget {
  const _ProfilesEmptyState({required this.onAdd, required this.onQuickAdd});

  final VoidCallback onAdd;
  final ValueChanged<SshLink> onQuickAdd;

  @override
  State<_ProfilesEmptyState> createState() => _ProfilesEmptyStateState();
}

/// Offers a server guide link too, since most people who never connect have
/// nothing to connect to yet.
class _ProfilesEmptyStateState extends State<_ProfilesEmptyState> {
  final _quickAdd = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _quickAdd.dispose();
    super.dispose();
  }

  void _submitQuickAdd() {
    final link = parseSshTarget(_quickAdd.text);
    setState(() => _invalid = link == null && _quickAdd.text.trim().isNotEmpty);
    if (link == null) return;
    _quickAdd.clear();
    widget.onQuickAdd(link);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return EmptyStatePanel(
      icon: PhosphorIconsFill.terminalWindow,
      title: t.profiles.emptyMachinesTitle,
      subtitle: t.profiles.emptyMachinesSubtitle,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 320,
            child: AppInlineAddField(
              controller: _quickAdd,
              hint: t.profiles.quickAddHint,
              addTooltip: t.profiles.quickAddTooltip,
              keyboardType: TextInputType.url,
              onSubmit: _submitQuickAdd,
            ),
          ),
          if (_invalid) ...[
            const SizedBox(height: 8),
            Text(
              t.profiles.quickAddInvalid,
              textAlign: TextAlign.center,
              style: context.colors.uiSmall.copyWith(
                color: context.colors.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Tooltip(
            message: t.profiles.addMachineButton,
            child: ElevatedButton.icon(
              onPressed: widget.onAdd,
              icon: const Icon(PhosphorIconsRegular.plus, size: 18),
              label: Text(t.profiles.addFirstMachine),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => showServerGuideSheet(context),
            child: Text(t.profiles.noServerYet),
          ),
        ],
      ),
    );
  }
}

enum _SessionRowAction { rename, detach, end }

/// One tab stitched under its profile card: green when connected, the accent
/// with a spinner while the handshake is still in flight, amber when its
/// remote session is only detached (alive on the server, no live connection
/// here), and a plain dim label for a dropped tab with nothing on the server
/// to reattach to - a plain SSH connection that just died.
///
/// Only the group's last row closes the block off with a rounded bottom and
/// no bottom border; its top edge doubles as the separator from the row
/// above.
class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    required this.session,
    required this.isLast,
    required this.onTap,
    this.onRename,
    this.onDetach,
    this.onEnd,
  });

  final ActiveSessionView session;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDetach;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final status = SessionStatus.of(session, t, context.colors);
    final connecting = status.connecting;
    final connected = status.connected;
    final accentColor = status.color;
    final hasMenu = onRename != null || onDetach != null || onEnd != null;
    final anonymize = ref.watch(anonymizeProvider);
    final radius = isLast
        ? const BorderRadius.vertical(
            bottom: Radius.circular(AppTheme.radiusMd),
          )
        : BorderRadius.zero;

    return Material(
      color: context.colors.surfaceElevated.invisible,
      borderRadius: radius,
      child: Ink(
        decoration: BoxDecoration(
          color: context.colors.surfaceElevated,
          borderRadius: radius,
          border: Border(
            top: BorderSide(color: context.colors.surfaceBorder),
            left: BorderSide(color: context.colors.surfaceBorder),
            right: BorderSide(color: context.colors.surfaceBorder),
            bottom: isLast
                ? BorderSide(color: context.colors.surfaceBorder)
                : BorderSide.none,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 8, 11),
            child: Row(
              children: [
                if (connecting)
                  SizedBox.square(
                    dimension: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: accentColor,
                    ),
                  )
                else
                  Icon(
                    connected
                        ? PhosphorIconsFill.circle
                        : PhosphorIconsRegular.circle,
                    size: 9,
                    color: accentColor,
                  ),
                SizedBox(width: connecting ? 10 : 12),
                Expanded(
                  child: Text(
                    sessionDisplayName(session, anonymize: anonymize),
                    style: context.colors.uiStyle.copyWith(
                      fontSize: 13,
                      color: connected || connecting
                          ? context.colors.textPrimary
                          : context.colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: connected ? FontWeight.w400 : FontWeight.w600,
                    color: accentColor,
                  ),
                ),
                if (hasMenu)
                  Builder(
                    builder: (menuCtx) {
                      final mt = Translations.of(menuCtx);
                      return AppActionDropdown<_SessionRowAction>(
                        iconSize: 16,
                        width: 220,
                        items: [
                          if (onRename != null)
                            DropdownItem(
                              value: _SessionRowAction.rename,
                              intrinsicHeight: true,
                              child: AppDropdownItem(
                                icon: PhosphorIconsRegular.pencilSimple,
                                label: mt.session.rename,
                              ),
                            ),
                          if (onDetach != null)
                            DropdownItem(
                              value: _SessionRowAction.detach,
                              intrinsicHeight: true,
                              child: AppDropdownItem(
                                icon: PhosphorIconsRegular.arrowLineDown,
                                label: mt.session.detach,
                              ),
                            ),
                          if (onEnd != null)
                            DropdownItem(
                              value: _SessionRowAction.end,
                              intrinsicHeight: true,
                              child: AppDropdownItem(
                                icon: PhosphorIconsRegular.trash,
                                label: mt.session.endSession,
                                color: context.colors.error,
                              ),
                            ),
                        ],
                        onSelected: (action) {
                          switch (action) {
                            case _SessionRowAction.rename:
                              onRename?.call();
                            case _SessionRowAction.detach:
                              onDetach?.call();
                            case _SessionRowAction.end:
                              onEnd?.call();
                          }
                        },
                      );
                    },
                  )
                else
                  const SizedBox(width: 6),
                Icon(
                  PhosphorIconsFill.caretRight,
                  size: 16,
                  color: connected || connecting
                      ? context.colors.textTertiary
                      : context.colors.textTertiary.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Always the last thing stitched under a machine, connected and detached
/// sessions alike - a dedicated way to start a fresh session without having
/// to repurpose a tap on the card or on one of its existing rows.
class _NewSessionRow extends StatelessWidget {
  const _NewSessionRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    const radius = BorderRadius.vertical(
      bottom: Radius.circular(AppTheme.radiusMd),
    );
    return Material(
      color: context.colors.surfaceElevated.invisible,
      borderRadius: radius,
      child: Ink(
        decoration: BoxDecoration(
          color: context.colors.surfaceElevated,
          borderRadius: radius,
          border: Border(
            top: BorderSide(color: context.colors.surfaceBorder),
            left: BorderSide(color: context.colors.surfaceBorder),
            right: BorderSide(color: context.colors.surfaceBorder),
            bottom: BorderSide(color: context.colors.surfaceBorder),
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsRegular.plus,
                  size: 16,
                  color: context.colors.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  t.terminal.newSession,
                  style: context.colors.uiStyle.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
