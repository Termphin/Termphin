import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/port_forwarding_rule.dart';
import '../models/ssh_profile.dart';
import '../services/ssh/ssh_session_manager.dart';
import 'ssh_session_manager_provider.dart';

class TunnelEntry {
  const TunnelEntry({
    required this.rule,
    required this.isFromProfile,
    this.status = TunnelStatus.idle,
    this.errorMessage,
  });

  final PortForwardingRule rule;
  final bool isFromProfile;
  final TunnelStatus status;
  final String? errorMessage;

  TunnelEntry copyWith({
    TunnelStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TunnelEntry(
      rule: rule,
      isFromProfile: isFromProfile,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class PortForwardingState {
  const PortForwardingState({this.entries = const {}});

  final Map<String, TunnelEntry> entries;

  PortForwardingState copyWith({Map<String, TunnelEntry>? entries}) {
    return PortForwardingState(entries: entries ?? this.entries);
  }
}

final portForwardingProvider =
    NotifierProvider.family<
      PortForwardingNotifier,
      PortForwardingState,
      String
    >(PortForwardingNotifier.new);

class PortForwardingNotifier extends Notifier<PortForwardingState> {
  PortForwardingNotifier(this._sessionId);

  final String _sessionId;
  late final SshSessionManager _manager;
  final Map<String, PortForwardingRule> _openTunnels = {};
  bool _disposed = false;

  @override
  PortForwardingState build() {
    _disposed = false;
    _manager = ref.read(sshSessionManagerProvider);
    ref.onDispose(() {
      _disposed = true;
      stopAll();
    });
    return const PortForwardingState();
  }

  void loadProfileRules(SshProfile profile) {
    final entries = <String, TunnelEntry>{};
    for (final rule in profile.portForwardings) {
      entries[rule.id] = TunnelEntry(
        rule: rule,
        isFromProfile: true,
        status: TunnelStatus.idle,
      );
    }
    state = state.copyWith(entries: entries);
  }

  /// `starting` counts as taken: the state flips before the open is awaited,
  /// so a second tap during the round trip would open a listener nothing
  /// holds a handle to any more.
  Future<void> startTunnel(
    PortForwardingRule rule, {
    bool isFromProfile = false,
  }) async {
    if (_disposed) return;
    final existing = state.entries[rule.id];
    if (existing != null &&
        (existing.status == TunnelStatus.active ||
            existing.status == TunnelStatus.starting)) {
      return;
    }

    state = state.copyWith(
      entries: {
        ...state.entries,
        rule.id: TunnelEntry(
          rule: rule,
          isFromProfile: isFromProfile,
          status: TunnelStatus.starting,
        ),
      },
    );

    try {
      await _manager.openTunnel(
        _sessionId,
        rule.id,
        rule.type.name,
        rule.localPort,
        rule.remoteHost,
        rule.remotePort,
        rule.localHost,
      );
      _openTunnels[rule.id] = rule;

      if (_disposed) {
        await _manager.closeTunnel(_sessionId, rule.id, rule.type.name);
        _openTunnels.remove(rule.id);
        return;
      }
      state = state.copyWith(
        entries: {
          ...state.entries,
          rule.id: TunnelEntry(
            rule: rule,
            isFromProfile: isFromProfile,
            status: TunnelStatus.active,
          ),
        },
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        entries: {
          ...state.entries,
          rule.id: TunnelEntry(
            rule: rule,
            isFromProfile: isFromProfile,
            status: TunnelStatus.error,
            errorMessage: e.toString().replaceFirst('Exception: ', ''),
          ),
        },
      );
    }
  }

  /// Closes the tunnel and parks the rule at [TunnelStatus.idle].
  ///
  /// The rule stays either way - an ad-hoc rule used to be dropped here, which
  /// made the panel's off switch a delete button with no warning and no undo.
  /// Removing one is [removeAdhocTunnel], which the panel offers separately.
  Future<void> stopTunnel(String ruleId) async {
    final entry = state.entries[ruleId];
    if (entry == null) return;

    await _manager.closeTunnel(_sessionId, ruleId, entry.rule.type.name);
    _openTunnels.remove(ruleId);
    if (_disposed) return;

    state = state.copyWith(
      entries: {
        ...state.entries,
        ruleId: entry.copyWith(status: TunnelStatus.idle, clearError: true),
      },
    );
  }

  /// Drops an ad-hoc rule, closing its tunnel first. A profile's rule is not
  /// this session's to delete - it is edited on the profile.
  Future<void> removeAdhocTunnel(String ruleId) async {
    final entry = state.entries[ruleId];
    if (entry == null || entry.isFromProfile) return;

    await _manager.closeTunnel(_sessionId, ruleId, entry.rule.type.name);
    _openTunnels.remove(ruleId);
    if (_disposed) return;

    final newEntries = Map<String, TunnelEntry>.from(state.entries)
      ..remove(ruleId);
    state = state.copyWith(entries: newEntries);
  }

  Future<void> startAllProfileRules() async {
    final profileRules = state.entries.values
        .where((e) => e.isFromProfile && e.status == TunnelStatus.idle)
        .toList();

    for (final entry in profileRules) {
      await startTunnel(entry.rule, isFromProfile: true);
    }
  }

  void stopAll() {
    for (final rule in _openTunnels.values) {
      unawaited(_manager.closeTunnel(_sessionId, rule.id, rule.type.name));
    }
    _openTunnels.clear();

    if (_disposed) return;

    final newEntries = <String, TunnelEntry>{};
    for (final entry in state.entries.entries) {
      if (entry.value.isFromProfile) {
        newEntries[entry.key] = entry.value.copyWith(
          status: TunnelStatus.idle,
          clearError: true,
        );
      }
    }
    state = state.copyWith(entries: newEntries);
  }

  /// Applies an edited ad-hoc [rule], which keeps its id. A live tunnel is
  /// torn down and reopened on the new ports - leaving the old listener up
  /// would serve the rule the user just replaced.
  Future<void> updateAdhocTunnel(PortForwardingRule rule) async {
    final entry = state.entries[rule.id];
    if (entry == null || entry.isFromProfile) return;
    final wasActive = entry.status == TunnelStatus.active;

    if (wasActive) {
      await _manager.closeTunnel(_sessionId, rule.id, entry.rule.type.name);
      _openTunnels.remove(rule.id);
    }
    if (_disposed) return;

    state = state.copyWith(
      entries: {
        ...state.entries,
        rule.id: TunnelEntry(
          rule: rule,
          isFromProfile: false,
          status: TunnelStatus.idle,
        ),
      },
    );
    if (wasActive) await startTunnel(rule);
  }

  void addAdhocTunnel(PortForwardingRule rule) {
    state = state.copyWith(
      entries: {
        ...state.entries,
        rule.id: TunnelEntry(
          rule: rule,
          isFromProfile: false,
          status: TunnelStatus.idle,
        ),
      },
    );
  }
}
